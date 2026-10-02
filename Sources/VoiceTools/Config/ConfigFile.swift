import Foundation
import TOMLDecoder

/// Everything config.toml holds: settings and tracks. (Vocabulary is in vocabulary.toml beside it.)
struct AppConfig: Equatable {
    var appearance: AppearanceChoice = .auto
    var tracks: [Track]
}

/// A problem found reading config.toml or vocabulary.toml. Errors stop the file from applying (the last good version
/// keeps running); warnings apply but are reported. `path` names where, e.g. `track[clean-dictation].step[4].model`.
struct ConfigIssue: Error, Hashable, CustomStringConvertible {
    enum Severity: String { case error, warning }
    var severity: Severity
    var path: String
    var message: String
    var line: Int?

    var description: String {
        let place = [line.map { "line \($0)" }, path.isEmpty ? nil : path].compactMap { $0 }.joined(separator: ", ")
        return place.isEmpty ? message : "\(place): \(message)"
    }
}

/// The parsed TOML, as a tree we can walk with good error messages (paths, "did you mean").
indirect enum TOMLValue: Decodable, Equatable {
    case string(String), int(Int), double(Double), bool(Bool), date(Date), array([TOMLValue]), table([String: TOMLValue])

    /// Scalars first: TOMLDecoder hands back the parent table when a keyed container is requested for a scalar,
    /// so trying tables first would recurse forever.
    init(from decoder: Decoder) throws {
        func scalar<T: Decodable>(_ type: T.Type) -> T? { (try? decoder.singleValueContainer()).flatMap { try? $0.decode(type) } }
        if let v = scalar(Bool.self) { self = .bool(v) }
        else if let v = scalar(Int.self) { self = .int(v) }
        else if let v = scalar(Double.self) { self = .double(v) }
        else if let v = scalar(String.self) { self = .string(v) }
        else if let v = scalar(Date.self) { self = .date(v) }
        else if var unkeyed = try? decoder.unkeyedContainer() {
            var array: [TOMLValue] = []
            while !unkeyed.isAtEnd { array.append(try unkeyed.decode(TOMLValue.self)) }
            self = .array(array)
        } else {
            let keyed = try decoder.container(keyedBy: AnyKey.self)
            var table: [String: TOMLValue] = [:]
            for key in keyed.allKeys { table[key.stringValue] = try keyed.decode(TOMLValue.self, forKey: key) }
            self = .table(table)
        }
    }

    var typeName: String {
        switch self {
        case .string: "a string"
        case .int: "an integer"
        case .double: "a number"
        case .bool: "true or false"
        case .date: "a date"
        case .array: "a list"
        case .table: "a table"
        }
    }
}

struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

/// Reads one TOML table, recording which keys were used and what went wrong, with the table's path.
struct TableReader {
    let table: [String: TOMLValue]
    let path: String
    private(set) var used: Set<String> = []
    var issues: [ConfigIssue] = []

    init(_ table: [String: TOMLValue], path: String) {
        self.table = table
        self.path = path
    }

    private func at(_ key: String) -> String { path.isEmpty ? key : "\(path).\(key)" }

    mutating func error(_ key: String?, _ message: String) {
        issues.append(ConfigIssue(severity: .error, path: key.map(at) ?? path, message: message))
    }

    mutating func warning(_ key: String?, _ message: String) {
        issues.append(ConfigIssue(severity: .warning, path: key.map(at) ?? path, message: message))
    }

    mutating func raw(_ key: String) -> TOMLValue? {
        used.insert(key)
        return table[key]
    }

    mutating func string(_ key: String, required: Bool = false) -> String? {
        switch raw(key) {
        case .string(let v): return v
        case nil: if required { error(key, "is required") }; return nil
        case let other?: error(key, "should be a string, not \(other.typeName)"); return nil
        }
    }

    mutating func bool(_ key: String) -> Bool? {
        switch raw(key) {
        case .bool(let v): return v
        case nil: return nil
        case let other?: error(key, "should be true or false, not \(other.typeName)"); return nil
        }
    }

    mutating func number(_ key: String) -> Double? {
        switch raw(key) {
        case .double(let v): return v
        case .int(let v): return Double(v)
        case nil: return nil
        case let other?: error(key, "should be a number, not \(other.typeName)"); return nil
        }
    }

    mutating func int(_ key: String) -> Int? {
        switch raw(key) {
        case .int(let v): return v
        case nil: return nil
        case let other?: error(key, "should be a whole number, not \(other.typeName)"); return nil
        }
    }

    mutating func strings(_ key: String) -> [String]? {
        switch raw(key) {
        case .array(let items):
            var out: [String] = []
            for (i, item) in items.enumerated() {
                if case .string(let s) = item { out.append(s) } else { error("\(key)[\(i)]", "should be a string") }
            }
            return out
        case nil: return nil
        case let other?: error(key, "should be a list of strings, not \(other.typeName)"); return nil
        }
    }

    mutating func tables(_ key: String) -> [[String: TOMLValue]]? {
        switch raw(key) {
        case .array(let items):
            var out: [[String: TOMLValue]] = []
            for (i, item) in items.enumerated() {
                if case .table(let t) = item { out.append(t) } else { error("\(key)[\(i)]", "should be a table") }
            }
            return out
        case nil: return nil
        case let other?: error(key, "should be a list of tables, not \(other.typeName)"); return nil
        }
    }

    mutating func stringTable(_ key: String) -> [String: String]? {
        switch raw(key) {
        case .table(let t):
            var out: [String: String] = [:]
            for (k, v) in t {
                if case .string(let s) = v { out[k] = s } else { error("\(key).\(k)", "should be a string") }
            }
            return out
        case nil: return nil
        case let other?: error(key, "should be a table of strings, not \(other.typeName)"); return nil
        }
    }

    /// One of `allowed`, or an error naming them.
    mutating func choice(_ key: String, _ allowed: [String], default fallback: String? = nil) -> String? {
        guard let value = string(key) else { return fallback }
        guard allowed.contains(value) else {
            error(key, "'\(value)' isn't one of: \(allowed.joined(separator: ", "))\(Self.suggestion(value, allowed))")
            return fallback
        }
        return value
    }

    /// Warnings for keys nobody read: usually a typo, so suggest the closest known key.
    mutating func finish(known: [String]) {
        for key in table.keys.sorted() where !used.contains(key) {
            warning(key, "isn't a setting here, so it's ignored\(Self.suggestion(key, known))")
        }
    }

    static func suggestion(_ word: String, _ options: [String]) -> String {
        let best = options.map { ($0, Self.distance(word.lowercased(), $0.lowercased())) }.min { $0.1 < $1.1 }
        guard let best, best.1 <= max(2, word.count / 3) else { return "" }
        return " (did you mean '\(best.0)'?)"
    }

    private static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        var row = Array(0...b.count)
        for i in 1...max(a.count, 1) where !a.isEmpty {
            var previous = row[0]
            row[0] = i
            for j in 1...max(b.count, 1) where !b.isEmpty {
                let current = row[j]
                row[j] = min(row[j] + 1, row[j - 1] + 1, previous + (a[i - 1] == b[j - 1] ? 0 : 1))
                previous = current
            }
        }
        return row[b.count]
    }
}

/// config.toml ⇄ the app's tracks and settings.
enum ConfigFile {
    static let version = 1

    // MARK: Names used in the file

    static let colors: [(String, String)] = [
        ("apricot", "#F0A35E"), ("dusk-blue", "#8FB8D6"), ("lavender", "#C3A3D4"), ("sage", "#A9BF8A"),
        ("marigold", "#E8C26A"), ("rose", "#EC8F7C"), ("red-rock", "#E0694A"),
    ]
    static let stepTypes = ["microphone", "text", "transcribe", "llm", "route", "http", "template", "fix-words",
                            "paste", "copy", "speak", "show-hud"]
    static let textSources: [(String, TextSource)] = [
        ("selection", .selection), ("page", .page), ("clipboard", .clipboard), ("previous-clipboard", .previousClipboard),
    ]
    static let parakeetModes: [(String, ParakeetMode)] = [("on-release", .onRelease), ("pause-chunks", .pauseChunks), ("streaming", .streaming)]
    static let localSpeechModels = ["pocket", "supertonic", "macos"]

    /// `fast-dictation` from "Fast dictation".
    static func slug(_ name: String) -> String {
        let lowered = name.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        let collapsed = String(lowered).split(separator: "-").joined(separator: "-")
        return collapsed.isEmpty ? "track" : collapsed
    }

    static func isValidSlug(_ s: String) -> Bool {
        !s.isEmpty && s.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "-" } && s.first != "-" && s.last != "-"
    }

    /// Gives every track a unique slug, keeping the ones it has.
    static func assignSlugs(_ tracks: inout [Track]) {
        var seen = Set<String>()
        for i in tracks.indices {
            var base = tracks[i].slug.flatMap { isValidSlug($0) ? $0 : nil } ?? slug(tracks[i].name)
            if seen.contains(base) {
                var n = 2
                while seen.contains("\(base)-\(n)") { n += 1 }
                base = "\(base)-\(n)"
            }
            tracks[i].slug = base
            seen.insert(base)
        }
    }

    // MARK: Reading

    struct Result {
        var config: AppConfig?
        var errors: [ConfigIssue]
        var warnings: [ConfigIssue]
    }

    /// Parses and checks the file. `config` is nil when there are errors.
    /// `existing` keeps tracks' in-app identities (UUIDs) stable across reloads, matched by slug.
    static func parse(_ text: String, existing: [Track] = []) -> Result {
        let root: [String: TOMLValue]
        do {
            guard case .table(let t) = try TOMLDecoder().decode(TOMLValue.self, from: text) else {
                return Result(config: nil, errors: [ConfigIssue(severity: .error, path: "", message: "isn't a TOML table")], warnings: [])
            }
            root = t
        } catch {
            return Result(config: nil, errors: [syntaxIssue(error)], warnings: [])
        }

        var top = TableReader(root, path: "")
        if let v = top.int("version"), v != version {
            top.error("version", "is \(v), but this Voice Pipes reads version \(version)")
        }
        var appearance = AppearanceChoice.auto
        if case .table(let settingsTable)? = top.raw("settings") {
            var settings = TableReader(settingsTable, path: "settings")
            if let a = settings.choice("appearance", AppearanceChoice.allCases.map(\.rawValue)) { appearance = AppearanceChoice(rawValue: a) ?? .auto }
            settings.finish(known: ["appearance"])
            top.issues += settings.issues
        } else if root["settings"] != nil {
            top.error("settings", "should be a table: [settings]")
        }

        var tracks: [Track] = []
        var seen = Set<String>()
        for (index, table) in (top.tables("track") ?? []).enumerated() {
            let label = (table["id"].flatMap { if case .string(let s) = $0 { s } else { nil } }) ?? "\(index)"
            var reader = TableReader(table, path: "track[\(label)]")
            if var track = readTrack(&reader) {
                if let slug = track.slug {
                    if seen.contains(slug) { reader.error("id", "'\(slug)' is used by another track; ids must be unique") }
                    seen.insert(slug)
                    if let match = existing.first(where: { $0.slug == slug }) { track.id = match.id }
                }
                tracks.append(track)
            }
            top.issues += reader.issues
        }
        top.finish(known: ["version", "settings", "track"])

        let errors = top.issues.filter { $0.severity == .error }
        let warnings = top.issues.filter { $0.severity == .warning }
        return Result(config: errors.isEmpty ? AppConfig(appearance: appearance, tracks: tracks) : nil, errors: errors, warnings: warnings)
    }

    static func syntaxIssue(_ error: Error) -> ConfigIssue {
        let text = "\(error)"
        var line: Int?
        if let range = text.range(of: #"\(Line (\d+)\)"#, options: .regularExpression) {
            line = Int(text[range].filter(\.isNumber))
        }
        let message = text.components(separatedBy: "Underlying error: ").last.map {
            $0.replacingOccurrences(of: #"\(Line \d+\) "#, with: "", options: .regularExpression)
        } ?? text
        return ConfigIssue(severity: .error, path: "", message: "isn't valid TOML: \(message.trimmingCharacters(in: CharacterSet(charactersIn: ". ")))", line: line)
    }

    private static func readTrack(_ r: inout TableReader) -> Track? {
        let name = r.string("name", required: true) ?? ""
        var slug = r.string("id")
        if let s = slug, !isValidSlug(s) {
            r.error("id", "'\(s)' should use lowercase letters, digits and dashes, e.g. '\(Self.slug(s))'")
            slug = nil
        } else if slug == nil {
            r.warning("id", "is missing; using '\(Self.slug(name))'. Give each track an id so the CLI can find it")
            slug = Self.slug(name)
        }
        var colorHex = "#A9BF8A"
        if let color = r.string("color") {
            if let named = colors.first(where: { $0.0 == color }) {
                colorHex = named.1
            } else if color.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil {
                colorHex = color.uppercased()
            } else {
                r.error("color", "'\(color)' should be \(colors.map(\.0).joined(separator: ", ")) or \"#RRGGBB\"\(TableReader.suggestion(color, colors.map(\.0)))")
            }
        }
        let enabled = r.bool("enabled") ?? true

        var triggers: [Trigger] = []
        for (i, hotkey) in (r.tables("hotkeys") ?? []).enumerated() {
            var h = TableReader(hotkey, path: "\(r.path).hotkeys[\(i)]")
            if let keys = h.string("keys", required: true) {
                do {
                    let combo = try KeyNames.parse(keys)
                    let mode = h.choice("mode", ["hold", "toggle"], default: "toggle") ?? "toggle"
                    triggers.append(Trigger(combo: combo, mode: mode == "hold" ? .hold : .toggle))
                } catch {
                    h.error("keys", "'\(keys)' \(error)")
                }
            }
            h.finish(known: ["keys", "mode"])
            r.issues += h.issues
        }

        var steps: [Step] = []
        let stepTables = r.tables("step") ?? []
        if stepTables.isEmpty { r.error("step", "a track needs at least one [[track.step]]") }
        for (i, table) in stepTables.enumerated() {
            var s = TableReader(table, path: "\(r.path).step[\(i + 1)]")
            if let kind = readStep(&s) { steps.append(Step(kind: kind)) }
            r.issues += s.issues
        }
        r.finish(known: ["id", "name", "color", "enabled", "hotkeys", "step"])
        return Track(slug: slug, name: name, colorHex: colorHex, enabled: enabled, triggers: triggers, steps: steps)
    }

    private static func readStep(_ s: inout TableReader) -> StepKind? {
        guard let type = s.string("type", required: true) else { return nil }
        let kind: StepKind?
        var known = ["type"]
        switch type {
        case "microphone":
            kind = .microphone
        case "text":
            known += ["sources"]
            var sources: [TextSource] = []
            for name in s.strings("sources") ?? ["selection", "page", "clipboard"] {
                if let source = textSources.first(where: { $0.0 == name })?.1 { sources.append(source) }
                else { s.error("sources", "'\(name)' isn't one of: \(textSources.map(\.0).joined(separator: ", "))") }
            }
            kind = .text(sources: sources)
        case "transcribe":
            known += ["model", "mode", "pause_ms"]
            let model = s.string("model") ?? "parakeet"
            if model == "parakeet" {
                let modeName = s.choice("mode", parakeetModes.map(\.0), default: "on-release") ?? "on-release"
                var pause = s.int("pause_ms") ?? 500
                if !(300...1200).contains(pause) {
                    s.error("pause_ms", "should be 300–1200 (milliseconds of silence that end a phrase)")
                    pause = 500
                }
                kind = .parakeet(chunkOnPauseMs: pause, mode: parakeetModes.first { $0.0 == modeName }?.1)
            } else {
                if s.raw("mode") != nil { s.warning("mode", "only applies to model = \"parakeet\"") }
                if s.raw("pause_ms") != nil { s.warning("pause_ms", "only applies to model = \"parakeet\"") }
                if !model.contains("/") { s.error("model", "'\(model)' should be \"parakeet\" or an OpenRouter model id like \"microsoft/mai-transcribe-2\"") }
                kind = .openRouterSTT(model: model)
            }
        case "llm":
            known += ["model", "prompt", "on_failure"]
            let model = s.string("model", required: true) ?? ""
            let prompt = s.string("prompt") ?? ""
            let failure = s.choice("on_failure", ["pass-through", "stop"], default: "pass-through")
            kind = .llm(model: model, prompt: prompt, onFailure: failure == "stop" ? .stop : .passThrough)
        case "route":
            known += ["route"]
            var routes: [Route] = []
            let tables = s.tables("route") ?? []
            if tables.isEmpty { s.error("route", "a route step needs at least one [[track.step.route]]") }
            for (i, table) in tables.enumerated() {
                var r = TableReader(table, path: "\(s.path).route[\(i + 1)]")
                let route = Route(name: r.string("name", required: true) ?? "", when: r.string("when") ?? "",
                                  model: r.string("model", required: true) ?? "", prompt: r.string("prompt") ?? "")
                r.finish(known: ["name", "when", "model", "prompt"])
                s.issues += r.issues
                routes.append(route)
            }
            kind = .route(routes: routes)
        case "http":
            known += ["url", "method", "headers", "body", "response_field"]
            kind = .http(url: s.string("url", required: true) ?? "",
                         method: s.choice("method", ["GET", "POST", "PUT", "PATCH"], default: "POST") ?? "POST",
                         headers: s.stringTable("headers") ?? [:], bodyTemplate: s.string("body") ?? "",
                         responseField: s.string("response_field") ?? "")
        case "template":
            known += ["template"]
            kind = .template(s.string("template", required: true) ?? "")
        case "fix-words":
            kind = .fixWords
        case "paste":
            known += ["restore_clipboard"]
            kind = .paste(restoreClipboard: s.bool("restore_clipboard") ?? true)
        case "copy":
            kind = .copy
        case "speak":
            known += ["model", "voice", "speed"]
            let model = s.string("model") ?? "pocket"
            var speed = Float(s.number("speed") ?? 1.0)
            if !(0.6...2.0).contains(speed) {
                s.error("speed", "should be 0.6–2.0")
                speed = 1
            }
            let voice = s.string("voice")
            switch model {
            case "pocket", "supertonic":
                let engine: LocalVoiceEngine = model == "pocket" ? .pocket : .supertonic
                let chosen = voice ?? engine.defaultVoice
                if !engine.voices.contains(chosen) {
                    s.error("voice", "'\(chosen)' isn't a \(engine.label) voice; `vp voices --model \(model)` lists them\(TableReader.suggestion(chosen, engine.voices))")
                }
                kind = .localSpeech(engine: engine, voice: chosen, rate: speed)
            case "macos":
                kind = .speak(voiceID: voice, rate: speed)
            default:
                if !model.contains("/") {
                    s.error("model", "'\(model)' should be pocket, supertonic, macos or an OpenRouter model id\(TableReader.suggestion(model, localSpeechModels))")
                }
                kind = .openRouterSpeech(model: model, voice: voice ?? "", rate: speed)
            }
        case "show-hud":
            kind = .showHUD
        default:
            s.error("type", "'\(type)' isn't a block type. Types: \(stepTypes.joined(separator: ", "))\(TableReader.suggestion(type, stepTypes))")
            kind = nil
        }
        s.finish(known: known)
        return kind
    }

    // MARK: Writing

    /// The canonical file: the same layout and comments every time, so diffs show only what changed.
    static func write(_ config: AppConfig) -> String {
        var tracks = config.tracks
        assignSlugs(&tracks)
        var out = header
        out += "version = \(version)\n\n"
        out += "[settings]\n"
        out += "appearance = \(quote(config.appearance.rawValue))  # auto (follow macOS) | daylight | sundown\n"
        for track in tracks { out += "\n" + write(track) }
        out += "\n" + reference
        return out
    }

    private static func write(_ track: Track) -> String {
        let rule = String(repeating: "─", count: max(4, 100 - track.name.count))
        var out = "# ── \(track.name) \(rule)\n"
        out += "[[track]]\n"
        out += "id = \(quote(track.slug ?? slug(track.name)))  # how the CLI and agents name it: vp run \(track.slug ?? slug(track.name))\n"
        out += "name = \(quote(track.name))\n"
        let color = colors.first { $0.1 == track.colorHex.uppercased() }?.0 ?? track.colorHex
        out += "color = \(quote(color))\n"
        out += "enabled = \(track.enabled)\n"
        if track.triggers.isEmpty {
            out += "hotkeys = []  # none: run it from the menu bar panel or `vp run`\n"
        } else {
            out += "hotkeys = [\n"
            for trigger in track.triggers {
                out += "  { keys = \(quote(KeyNames.format(trigger.combo))), mode = \(quote(trigger.mode == .hold ? "hold" : "toggle")) },\n"
            }
            out += "]\n"
        }
        for step in track.steps { out += "\n" + write(step.kind) }
        return out
    }

    private static func write(_ kind: StepKind) -> String {
        var lines = ["  [[track.step]]"]
        func add(_ key: String, _ value: String, _ comment: String? = nil) {
            lines.append("  \(key) = \(value)" + (comment.map { "  # \($0)" } ?? ""))
        }
        switch kind {
        case .microphone:
            add("type", quote("microphone"))
        case .text(let sources):
            add("type", quote("text"))
            add("sources", "[" + sources.map { s in quote(textSources.first { $0.1 == s }?.0 ?? "selection") }.joined(separator: ", ") + "]",
                "the first that has text wins")
        case .parakeet(let pause, let mode):
            add("type", quote("transcribe"))
            add("model", quote("parakeet"), "on this Mac; or an OpenRouter model id")
            let name = parakeetModes.first { $0.1 == (mode ?? .onRelease) }?.0 ?? "on-release"
            add("mode", quote(name), "on-release | pause-chunks | streaming")
            if mode == .pauseChunks { add("pause_ms", "\(pause)", "silence that ends a phrase, 300–1200") }
        case .openRouterSTT(let model):
            add("type", quote("transcribe"))
            add("model", quote(model), "OpenRouter; needs `vp auth login openrouter`")
        case .llm(let model, let prompt, let failure):
            add("type", quote("llm"))
            add("model", quote(model), "any OpenRouter model id: `vp models --capability text`")
            add("on_failure", quote(failure == .stop ? "stop" : "pass-through"), "pass-through | stop")
            add("prompt", multiline(prompt))
        case .route(let routes):
            add("type", quote("route"))
            for route in routes {
                lines.append("")
                lines.append("    [[track.step.route]]")
                lines.append("    name = \(quote(route.name))")
                lines.append("    when = \(multiline(route.when, indent: "    "))")
                lines.append("    model = \(quote(route.model))")
                lines.append("    prompt = \(multiline(route.prompt, indent: "    "))")
            }
        case .http(let url, let method, let headers, let body, let field):
            add("type", quote("http"))
            add("method", quote(method), "GET | POST | PUT | PATCH")
            add("url", quote(url), "{{input}} here is URL-encoded")
            add("headers", "{ " + headers.sorted { $0.key < $1.key }.map { "\(key($0.key)) = \(quote($0.value))" }.joined(separator: ", ") + " }",
                headers.isEmpty ? "e.g. { Authorization = \"Bearer ${secret:notion}\" }" : nil)
            add("body", multiline(body), "{{input}} or {{input_json}}")
            add("response_field", quote(field), "dotted path into a JSON reply, e.g. data.text; empty = whole body")
        case .template(let template):
            add("type", quote("template"))
            add("template", multiline(template), "{{input}} or {{input_json}}")
        case .fixWords:
            add("type", quote("fix-words"), "your vocabulary.toml, applied instantly on this Mac")
        case .paste(let restore):
            add("type", quote("paste"))
            add("restore_clipboard", "\(restore)", "put your clipboard back after pasting")
        case .copy:
            add("type", quote("copy"))
        case .speak(let voiceID, let rate):
            add("type", quote("speak"))
            add("model", quote("macos"), "pocket | supertonic | macos | an OpenRouter speech model")
            if let voiceID { add("voice", quote(voiceID)) }
            add("speed", number(rate), "0.6–2.0")
        case .localSpeech(let engine, let voice, let rate):
            add("type", quote("speak"))
            add("model", quote(engine == .pocket ? "pocket" : "supertonic"), "pocket | supertonic | macos | an OpenRouter speech model")
            add("voice", quote(voice), "`vp voices --model \(engine == .pocket ? "pocket" : "supertonic")` lists them")
            add("speed", number(rate), "0.6–2.0")
        case .openRouterSpeech(let model, let voice, let rate):
            add("type", quote("speak"))
            add("model", quote(model), "OpenRouter; needs `vp auth login openrouter`")
            add("voice", quote(voice), "`vp voices --model \(model)` lists them")
            add("speed", number(rate), "0.6–2.0")
        case .showHUD:
            add("type", quote("show-hud"), "shows the text at the bottom of the screen for a few seconds")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: TOML spelling

    static func quote(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            case "\r": out += "\\r"
            default:
                if scalar.value < 0x20 || scalar.value == 0x7F { out += String(format: "\\u%04X", scalar.value) }
                else { out.unicodeScalars.append(scalar) }
            }
        }
        return out + "\""
    }

    /// Long or multi-line text as a ''' literal block (no escaping needed); otherwise a quoted string.
    static func multiline(_ s: String, indent: String = "  ") -> String {
        let safe = !s.contains("'''") && !s.unicodeScalars.contains { ($0.value < 0x20 && $0 != "\n" && $0 != "\t") || $0.value == 0x7F }
            && !s.hasSuffix("'")
        guard safe, s.contains("\n") || s.count > 72 else { return quote(s) }
        return "'''\n" + s + "'''"
    }

    private static func key(_ k: String) -> String {
        k.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" } && !k.isEmpty ? k : quote(k)
    }

    private static func number(_ value: Float) -> String {
        let rounded = (Double(value) * 100).rounded() / 100
        return rounded == rounded.rounded() ? String(format: "%.1f", rounded) : String(rounded)
    }

    // MARK: Comments

    static let header = """
        #:schema ./config.schema.json
        # ════════════════════════════════════════════════════════════════════════════════════════════════════
        #  voice | pipes · config.toml
        # ════════════════════════════════════════════════════════════════════════════════════════════════════
        #
        #  Your tracks: pipelines of blocks you play with hotkeys. Audio goes in one end (or text), runs through
        #  each [[track.step]] in order, and comes out pasted, spoken, sent somewhere, or all three.
        #
        #  Editing this file
        #    • Save and Voice Pipes reloads it within a second. If something doesn't check out, the last good
        #      version keeps running and the menu bar panel and Setup → Checks say what's wrong, with the line.
        #    • Check without applying:  vp config check
        #    • Every save keeps a backup:  vp config backups,  vp config restore <n>
        #    • The app writes this file back when you edit tracks in its window, in this layout with these
        #      comments. Comments you add yourself aren't kept, so keep notes in a track's name or elsewhere.
        #    • The block reference is at the end of this file;  vp help config  prints it too.
        #
        #  Keys and secrets are never stored here.
        #    • Providers:  vp auth login openrouter   ·   vp auth set typesafe
        #    • Your own (for http blocks):  vp secret set <name>, then use ${secret:<name>} in a url, header or
        #      body. Environment variables work too: ${env:NAME}.
        #
        #  Vocabulary (the words Fix words corrects) lives beside this file, in vocabulary.toml.
        # ════════════════════════════════════════════════════════════════════════════════════════════════════


        """

    static let reference = """
        # ════════════════════════════════════════════════════════════════════════════════════════════════════
        #  Reference
        # ════════════════════════════════════════════════════════════════════════════════════════════════════
        #
        #  A track
        #    id        required · unique · lowercase letters, digits, dashes · what `vp run <id>` uses
        #    name      required · shown in the menu bar, HUD and History
        #    color     apricot | dusk-blue | lavender | sage | marigold | rose | red-rock | "#RRGGBB"
        #    enabled   true | false · a disabled track keeps its settings but its hotkeys do nothing
        #    hotkeys   [ { keys = "option+space", mode = "hold" }, … ]
        #              keys: modifiers (control, option, shift, command) then one key, joined with +:
        #                    a–z, 0–9, space, return, tab, escape, delete, f1–f20, left, right, up, down,
        #                    minus, equal, comma, period, slash, semicolon, quote, backslash, grave, …
        #              mode: hold (records while held) | toggle (press to start, again to stop)
        #    step      one [[track.step]] per block, in order. Each block takes the previous block's output:
        #              inputs give audio or text, transcribe turns audio into text, the rest take text.
        #
        #  Blocks ([[track.step]] type = …)                                     takes → gives
        #    microphone                                                          — → audio
        #    text         sources = ["selection", "page", "clipboard",          — → text
        #                            "previous-clipboard"]  (first with text wins)
        #    transcribe   model = "parakeet" (on this Mac) | an OpenRouter id   audio → text
        #                 mode = on-release | pause-chunks | streaming  (parakeet only)
        #                 pause_ms = 300–1200  (pause-chunks only)
        #    fix-words    your vocabulary.toml, instantly, on this Mac          text → text
        #    llm          model = an OpenRouter id · prompt = '''…''' ({{input}} places the text; without it the
        #                 text is the user message) · on_failure = pass-through | stop          text → text
        #    route        Jev picks one [[track.step.route]] by its `when`; that route's model answers with its
        #                 prompt. Each route: name, when, model, prompt. Without a Jev key the first route answers.
        #                                                                         text → text
        #    http         url, method (GET | POST | PUT | PATCH), headers = { … }, body, response_field
        #                 {{input}} (URL-encoded in the url) / {{input_json}}; ${secret:name} / ${env:NAME}
        #                                                                         text → text (the reply)
        #    template     template = "…{{input}}…"                              text → text
        #    paste        restore_clipboard = true | false  (pastes at the cursor)            text → text
        #    copy         leaves the text on the clipboard                     text → text
        #    speak        model = pocket | supertonic | macos | an OpenRouter speech model
        #                 voice = see `vp voices --model <model>` · speed = 0.6–2.0           text → —
        #    show-hud     shows the text at the bottom of the screen           text → text
        #
        #  Running a track from the CLI: `vp run <id>` starts it like its hotkey; `vp run <id> --text "…"` or
        #  piping text in (`echo … | vp run <id>`) starts at the first block that takes text; the final text
        #  is printed.
        # ════════════════════════════════════════════════════════════════════════════════════════════════════

        """
}
