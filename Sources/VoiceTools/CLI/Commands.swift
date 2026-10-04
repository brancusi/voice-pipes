import AppKit
import Foundation

enum VPCommands {
    /// The app's version. Run through the /usr/local/bin/vp link, Bundle.main is the link's folder (no
    /// Info.plist), so read the bundle the link resolves into.
    static var version: String {
        let app = CLIInstaller.executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let bundle = app.pathExtension == "app" ? Bundle(url: app) : nil
        return (bundle ?? Bundle.main).object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    static let table: [CommandSpec] = [
        CommandSpec(name: "status", usage: "vp status", summary: "App, permissions, models, keys, checks and config health", handler: status),
        CommandSpec(name: "tracks", usage: "vp tracks [show <id> | enable <id> | disable <id>]", summary: "List tracks, show one, or switch one on or off", handler: tracks),
        CommandSpec(name: "run", usage: "vp run <id> [--text \"…\" | piped text] [--max <s>] [--silence <s>]",
                    summary: "Run a track: text starts at its first text block; a mic track records until you stop talking",
                    values: ["text", "max", "silence"], handler: runTrack),
        CommandSpec(name: "say", usage: "vp say \"…\" [--model pocket|supertonic|macos|<openrouter-id>] [--voice <id>] [--speed 0.6–2.0]",
                    summary: "Speak text aloud", values: ["model", "voice", "speed", "text"], handler: say),
        CommandSpec(name: "speed", usage: "vp speed <0.6–2.0>", summary: "Change the speed of what's being read aloud, live",
                    handler: { parsed, out in
                        let value = try parsed.positional(0, "speed", usage: "vp speed 1.3")
                        out.emit(Out(any: try AppClient.request("speed", ["speed": value], launch: false)))
                    }),
        CommandSpec(name: "next", usage: "vp next", summary: "Jump to the next sentence of what's being read",
                    handler: { _, out in out.emit(Out(any: try AppClient.request("reading", ["action": "next"], launch: false))) }),
        CommandSpec(name: "prev", usage: "vp prev", summary: "Jump back a sentence in what's being read",
                    handler: { _, out in out.emit(Out(any: try AppClient.request("reading", ["action": "previous"], launch: false))) }),
        CommandSpec(name: "reading", usage: "vp reading [keys always|hover|click|never | click-away keep-reading|stop | key <action> <key>… | shortcut <action> <combo>|none]",
                    summary: "How readings are steered from the keyboard: when the HUD takes the keys, and which keys", handler: reading),
        CommandSpec(name: "stop", usage: "vp stop", summary: "Stop speaking or recording", handler: { _, out in try simple("stop", out) }),
        CommandSpec(name: "pause", usage: "vp pause", summary: "Pause reading aloud", handler: { _, out in try simple("pause", out) }),
        CommandSpec(name: "resume", usage: "vp resume", summary: "Resume reading aloud", handler: { _, out in try simple("resume", out) }),
        CommandSpec(name: "listen", usage: "vp listen [--max <s>] [--silence <s>] [--model parakeet|<openrouter-id>]",
                    summary: "Record until you stop talking, then print the transcript", values: ["max", "silence", "model"], handler: listen),
        CommandSpec(name: "ask", usage: "vp ask \"<question>\" [--max <s>] [--silence <s>] [--voice <id>] [--voice-model <m>] [--listen-model <m>]",
                    summary: "Speak a question, then record and print the spoken answer",
                    values: ["max", "silence", "voice", "voice-model", "listen-model", "speed"], handler: ask),
        CommandSpec(name: "transcribe", usage: "vp transcribe <audio-file> [--model parakeet|<openrouter-id>]",
                    summary: "Transcribe an audio file (on this Mac by default)", values: ["model"], handler: transcribe),
        CommandSpec(name: "history", usage: "vp history [show <n> | usage] [--limit <n>] [--track <id>] [--search <text>] [--since 30m|2h|3d]",
                    summary: "Recent runs and their logs: what was said, each step, Jev's picks, tokens and cost", values: ["limit", "track", "search", "since"], handler: history),
        CommandSpec(name: "vocab", usage: "vp vocab [add <word> --heard \"a, b\" [--exact] | remove <word> | test \"<sentence>\" | train <word>]",
                    summary: "The words Fix words corrects", values: ["heard"], switches: ["exact"], handler: vocab),
        CommandSpec(name: "config", usage: "vp config [check [file] | schema [vocabulary] | backups | restore <n> | reload | open | path]",
                    summary: "config.toml: check, schema, backups, reload", handler: config),
        CommandSpec(name: "models", usage: "vp models [--capability text|transcription|speech] [--search <text>] [--limit <n>]",
                    summary: "OpenRouter models for a job, with prices", values: ["capability", "search", "limit"], handler: models),
        CommandSpec(name: "voices", usage: "vp voices [--model pocket|supertonic|macos|<openrouter-id>]", summary: "Voices for a speech model",
                    values: ["model"], handler: voices),
        CommandSpec(name: "auth", usage: "vp auth [login openrouter [--headless | --code <code>] | set <provider> [--key <key> | piped] | remove <provider>]",
                    summary: "Provider keys (kept in the Keychain): OpenRouter, TypeSafe Jev", values: ["key", "code"], switches: ["headless"], handler: auth),
        CommandSpec(name: "secret", usage: "vp secret [set <name> [--value <v> | piped] | remove <name>]",
                    summary: "Your own secrets for http blocks, used as ${secret:<name>}", values: ["value"], handler: secret),
        CommandSpec(name: "watch", usage: "vp watch", summary: "Stream run events (recording, processing, speaking, done, failed) until interrupted", handler: watch),
        CommandSpec(name: "open", usage: "vp open [main | menu | reading | track <id> [--step n [--route n]] [--section title|triggers|pipeline] | history [--track <id>] [--search <text>] [--run n] | vocabulary [--word <w>] [--add] | setup [--section <name>] | onboarding [--step <name>] | about | config] [--field <name>] [--background]",
                    summary: "Show any window, page, block or field (it flashes); answers with what's on screen",
                    values: ["step", "route", "section", "track", "search", "run", "word", "field"], switches: ["add", "background"], handler: open),
        CommandSpec(name: "close", usage: "vp close [main | menu | reading | about | onboarding | sheet | all]", summary: "Close a window, the menu bar panel or an open sheet",
                    handler: { parsed, out in try uiReply("close", ["target": parsed.positionals.first ?? "main"], out) }),
        CommandSpec(name: "ui", usage: "vp ui", summary: "What's on screen: windows, page, open block, focused field",
                    handler: { _, out in try uiReply("ui", [:], out) }),
        CommandSpec(name: "update", usage: "vp update", summary: "Check for a new version", handler: { _, out in try simple("update.check", out) }),
        CommandSpec(name: "install", usage: "vp install [--dir <path>]", summary: "Link vp and voicepipes onto your PATH", values: ["dir"], handler: install),
        CommandSpec(name: "agents", usage: "vp agents [install [--hook] | uninstall | context | read-aloud [off|long|attention|all] [--long-text <chars>]]",
                    summary: "The agent skill, the Claude Code session hook, and what agents read aloud to you", values: ["long-text"], switches: ["hook"], handler: agents),
    ]

    // MARK: Home

    static func home(_ out: Output) throws {
        let app = (try? AppClient.request("ping", launch: false)).map { "running · \($0["version"] as? String ?? version)" }
            ?? "not running · starts when a command needs it"
        let (config, issues) = loadConfig()
        var pairs: [(String, Out)] = [
            ("bin", .string(binPath)),
            ("description", .string(CLI.description)),
            ("app", .string(app)),
            ("config", .string("\(ConfigPaths.tilde(ConfigPaths.config)) · \(issueSummary(issues))")),
        ]
        let tracks = config?.tracks ?? []
        pairs.append(("tracks", trackTable(tracks)))
        out.emit(.object(pairs), help: [
            "vp run <id> --text \"…\"   (send text through a track; prints what comes out)",
            "vp say \"…\"   ·   vp ask \"<question>\"   ·   vp listen",
            "vp tracks show <id>",
            "Edit \(ConfigPaths.tilde(ConfigPaths.config)), then run `vp config check`",
            "vp help   (every command)",
        ])
    }

    static var binPath: String {
        ConfigPaths.tilde(URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL)
    }

    // MARK: Status

    static func status(_ parsed: Parsed, _ out: Output) throws {
        guard AppClient.isRunning else {
            let (config, issues) = loadConfig()
            out.emit(.object([
                ("app", .string("not running")),
                ("config", .string("\(ConfigPaths.tilde(ConfigPaths.config)) · \(issueSummary(issues))")),
                ("tracks", .int(config?.tracks.count ?? 0)),
            ]), help: ["open -a \"Voice Pipes\"   (or any command that needs it starts it)", "vp config check"])
            return
        }
        let data = try AppClient.request("status")
        let checks = data["checks"] as? [[String: Any]] ?? []
        let counts = ["OK", "INFO", "WARN", "FAIL"].map { level in "\(checks.filter { $0["level"] as? String == level }.count) \(level.lowercased())" }
        let problems = checks.filter { ["WARN", "FAIL"].contains($0["level"] as? String ?? "") }
        let providers = data["providers"] as? [[String: Any]] ?? []
        let config = data["config"] as? [String: Any] ?? [:]
        let issues = config["issues"] as? [String] ?? []
        var pairs: [(String, Out)] = [
            ("app", .string("running · \(data["version"] as? String ?? "")")),
            ("permissions", .string("microphone \(data["microphone"] as? String ?? "?") · accessibility \(data["accessibility"] as? String ?? "?")")),
            ("models", Out(any: data["models"])),
            ("keys", .table(["provider", "set", "key"], providers.map { [.string($0["id"] as? String ?? ""), .bool($0["set"] as? Bool ?? false), .s($0["key"] as? String)] })),
            ("checks", .string(counts.joined(separator: ", "))),
        ]
        if !problems.isEmpty {
            pairs.append(("problems", .table(["level", "title", "detail"], problems.map {
                [.string($0["level"] as? String ?? ""), .string($0["title"] as? String ?? ""), .string(out.trim($0["detail"] as? String ?? "", 120))]
            })))
        }
        pairs.append(("config", .string("\(ConfigPaths.tilde(ConfigPaths.config)) · \(issues.isEmpty ? "ok" : "\(issues.count) issue\(issues.count == 1 ? "" : "s")")")))
        if let running = data["running"] as? [String: Any], !running.isEmpty { pairs.append(("running", Out(any: running))) }
        var help = ["vp tracks", "vp history --limit 5"]
        if providers.contains(where: { $0["set"] as? Bool == false }) { help.insert("vp auth login openrouter   ·   vp auth set typesafe --key <key>", at: 0) }
        if !issues.isEmpty { help.insert("vp config check", at: 0) }
        out.emit(.object(pairs), help: help)
    }

    // MARK: Tracks

    static func tracks(_ parsed: Parsed, _ out: Output) throws {
        let (config, issues) = loadConfig()
        guard var config else { throw AppClient.Failure(code: "config_invalid", message: "config.toml doesn't check out: \(issues.first?.description ?? "")", hint: "vp config check") }
        switch parsed.positionals.first {
        case nil, "list":
            out.emit(.object([("count", .int(config.tracks.count)), ("tracks", trackTable(config.tracks))]),
                     help: config.tracks.isEmpty ? ["vp open onboarding", "vp help config"] : ["vp tracks show <id>", "vp run <id> --text \"…\""])
        case "show":
            let track = try findTrack(config.tracks, try parsed.positional(1, "id", usage: "vp tracks show <id>"))
            out.emit(.object([("track", trackDetail(track, out))]), help: ["vp run \(track.slug ?? "<id>") --text \"…\"", "edit \(ConfigPaths.tilde(ConfigPaths.config)) (id = \"\(track.slug ?? "")\")"])
        case "enable", "disable":
            let on = parsed.positionals[0] == "enable"
            let id = try parsed.positional(1, "id", usage: "vp tracks \(parsed.positionals[0]) <id>")
            let index = try config.tracks.firstIndex(of: findTrack(config.tracks, id))!
            let changed = config.tracks[index].enabled != on
            config.tracks[index].enabled = on
            if changed { try writeConfig(config) }
            out.emit(.object([("track", .string(config.tracks[index].slug ?? id)), ("enabled", .bool(on)), ("changed", .bool(changed))]), help: ["vp tracks"])
        default:
            throw UsageError("unknown_subcommand", "vp tracks takes list, show, enable or disable.", hint: "vp tracks --help")
        }
    }

    static func trackTable(_ tracks: [Track]) -> Out {
        .table(["id", "name", "hotkeys", "enabled"], tracks.map { track in
            [.string(track.slug ?? ConfigFile.slug(track.name)), .string(track.name),
             .string(track.triggers.map { "\(KeyNames.format($0.combo)) \($0.mode == .hold ? "hold" : "toggle")" }.joined(separator: " / ")),
             .bool(track.enabled)]
        })
    }

    static func trackDetail(_ track: Track, _ out: Output) -> Out {
        .object([
            ("id", .string(track.slug ?? "")),
            ("name", .string(track.name)),
            ("enabled", .bool(track.enabled)),
            ("hotkeys", .list(track.triggers.map { .string("\(KeyNames.format($0.combo)) \($0.mode == .hold ? "hold" : "toggle")") })),
            ("steps", .table(["n", "block", "takes", "gives"], stepRows(track.steps, prefix: "", out: out))),
            ("takes_text", .bool(track.steps.contains { $0.kind.input == .text })),
        ])
    }

    /// A row per step; a Branch's branches and their steps follow it, numbered 2.easy, 2.medium.1, …
    static func stepRows(_ steps: [Step], prefix: String, out: Output) -> [[Out]] {
        steps.enumerated().flatMap { i, step -> [[Out]] in
            let n = prefix + "\(i + 1)"
            var rows: [[Out]] = [[.string(n), .string(out.trim(step.kind.title, 80)), .string(step.kind.input.rawValue), .string(step.kind.output.rawValue)]]
            if case .branch(_, let branches) = step.kind {
                for branch in branches {
                    rows.append([.string("\(n).\(branch.name)"), .string(branch.steps.isEmpty ? "branch · passes the text through" : "branch · " + out.trim(branch.when, 60)),
                                 .string("text"), .string((branch.steps.last?.kind.output ?? .text).rawValue)])
                    rows += stepRows(branch.steps, prefix: "\(n).\(branch.name).", out: out)
                }
            }
            return rows
        }
    }

    static func findTrack(_ tracks: [Track], _ id: String) throws -> Track {
        let key = id.lowercased()
        if let track = tracks.first(where: { $0.slug == key || $0.name.lowercased() == key }) { return track }
        throw AppClient.Failure(code: "no_such_track", message: "No track '\(id)'.\(TableReader.suggestion(id, tracks.compactMap(\.slug)))", hint: "vp tracks")
    }

    // MARK: Running

    static func runTrack(_ parsed: Parsed, _ out: Output) throws {
        let id = try parsed.positional(0, "id", usage: "vp run <id> [--text \"…\"]")
        var args: [String: Any] = ["track": id]
        if let text = textArgument(parsed, from: 1) { args["text"] = text }
        if let max = try parsed.double("max") { args["max"] = max }
        if let silence = try parsed.double("silence") { args["silence"] = silence }
        let data = try AppClient.request("run", args)
        out.emit(.object([("track", .string(data["track"] as? String ?? id)), ("ms", .int(data["ms"] as? Int ?? 0)),
                          ("text", .string(data["text"] as? String ?? ""))]),
                 help: ["vp history --limit 1   (timings per block)"])
    }

    static func say(_ parsed: Parsed, _ out: Output) throws {
        guard let text = textArgument(parsed, from: 0) else {
            throw UsageError("missing_text", "Nothing to say.", hint: "vp say \"Build passed\"   or   echo … | vp say")
        }
        var args: [String: Any] = ["text": text]
        if let model = parsed["model"] { args["model"] = model }
        if let voice = parsed["voice"] { args["voice"] = voice }
        if let speed = try parsed.double("speed") { args["speed"] = speed }
        let data = try AppClient.request("say", args)
        out.emit(.object([("said", .string(out.trim(text, 120))), ("model", .string(data["model"] as? String ?? "")), ("ms", .int(data["ms"] as? Int ?? 0))]),
                 help: ["vp voices --model <model>   (other voices)"])
    }

    static func simple(_ cmd: String, _ out: Output) throws {
        out.emit(Out(any: try AppClient.request(cmd)))
    }

    static func listen(_ parsed: Parsed, _ out: Output) throws {
        var args: [String: Any] = [:]
        if let max = try parsed.double("max") { args["max"] = max }
        if let silence = try parsed.double("silence") { args["silence"] = silence }
        if let model = parsed["model"] { args["model"] = model }
        let data = try AppClient.request("listen", args)
        out.emit(.object([("text", .string(data["text"] as? String ?? "")), ("seconds", .double(data["seconds"] as? Double ?? 0)), ("ms", .int(data["ms"] as? Int ?? 0))]))
    }

    static func ask(_ parsed: Parsed, _ out: Output) throws {
        guard let question = textArgument(parsed, from: 0) else {
            throw UsageError("missing_question", "What should I ask?", hint: "vp ask \"Which branch should I deploy?\"")
        }
        var args: [String: Any] = ["question": question]
        if let v = parsed["voice"] { args["voice"] = v }
        if let v = parsed["voice-model"] { args["voice_model"] = v }   // speaks the question
        if let v = parsed["listen-model"] { args["model"] = v }        // transcribes the answer
        for key in ["max", "silence", "speed"] { if let v = try parsed.double(key) { args[key] = v } }
        let data = try AppClient.request("ask", args)
        out.emit(.object([("question", .string(out.trim(question, 120))), ("answer", .string(data["text"] as? String ?? "")),
                          ("seconds", .double(data["seconds"] as? Double ?? 0))]))
    }

    static func transcribe(_ parsed: Parsed, _ out: Output) throws {
        let path = try parsed.positional(0, "audio-file", usage: "vp transcribe <audio-file>")
        var args: [String: Any] = ["path": URL(fileURLWithPath: path).standardizedFileURL.path]
        if let model = parsed["model"] { args["model"] = model }
        let data = try AppClient.request("transcribe", args)
        out.emit(.object([("text", .string(data["text"] as? String ?? "")), ("seconds", .double(data["seconds"] as? Double ?? 0)), ("ms", .int(data["ms"] as? Int ?? 0))]))
    }

    static func watch(_ parsed: Parsed, _ out: Output) throws {
        if !out.json { print("events{at,event,track,detail}:") }
        _ = try AppClient.request("watch") { event in
            guard event["event"] as? String != "watch.started" else { return }
            if out.json {
                if let data = try? JSONSerialization.data(withJSONObject: event, options: [.sortedKeys]) { print(String(data: data, encoding: .utf8) ?? "") }
            } else {
                let detail = (event["error"] as? String) ?? (event["text"] as? String).map { out.trim($0, 100) } ?? (event["ms"] as? Int).map { "\($0) ms" } ?? ""
                print("  " + [Out.string(event["at"] as? String ?? ""), .string(event["event"] as? String ?? ""),
                              .string(event["track"] as? String ?? ""), .string(detail)].map(\.scalar).joined(separator: ","))
            }
            fflush(stdout)
        }
    }

    // MARK: History

    static func history(_ parsed: Parsed, _ out: Output) throws {
        let records = (try? Data(contentsOf: HistoryStore.defaultURL)).flatMap { try? JSONDecoder().decode([RunRecord].self, from: $0) } ?? []
        if parsed.positionals.first == "show" {
            let n = Int(try parsed.positional(1, "n", usage: "vp history show <n>   (1 = newest)")) ?? 0
            guard n >= 1, n <= records.count else {
                throw AppClient.Failure(code: "no_such_run", message: "There are \(records.count) runs; ask for 1–\(records.count).", hint: "vp history")
            }
            let r = records[n - 1]
            var pairs: [(String, Out)] = [("n", .int(n)), ("track", .string(r.trackName)), ("at", .string(ISO8601DateFormatter().string(from: r.date))),
                                          ("ms", .int(r.totalMs))]
            if let heard = r.heard { pairs.append(("heard", .string(heard))) }
            pairs.append(("text", .string(r.text)))
            if let failure = r.failure { pairs.append(("failure", .string(failure))) }
            if let log = r.log {
                // Step by step: branches indented, Jev's picks and what each step used and gave.
                pairs.append(("log", .table(["step", "ms", "used", "out"], log.map { e in
                    var used = RunLogFormat.usage(e)
                    if let others = e.decision?.others, !others.isEmpty { used += " (not taken: \(others.joined(separator: ", ")))" }
                    let outText = e.status == .ok ? (e.output ?? "") : (e.message ?? "failed")
                    return [.string(String(repeating: "  ", count: e.depth) + e.title), .int(e.ms), .string(used),
                            .string(out.trim(outText.replacingOccurrences(of: "\n", with: " "), out.full ? 2000 : 80))]
                })))
                pairs.append(("total", .string(UsageSummary([r]).line ?? "on this Mac")))
            } else {
                pairs.append(("steps", .table(["block", "ms"], r.steps.map { [.string($0.title), .int($0.ms)] })))
            }
            return out.emit(.object(pairs), help: r.log == nil ? [] : ["vp history show \(n) --full   (untrimmed outputs)"])
        }
        if parsed.positionals.first == "usage" {
            let now = Date()
            func summary(_ label: String, _ within: TimeInterval?) -> [Out] {
                let picked = records.filter { within == nil ? Calendar.current.isDateInToday($0.date) : now.timeIntervalSince($0.date) < within! }
                let s = UsageSummary(picked)
                return [.string(label), .int(s.runs), .int(s.promptTokens), .int(s.completionTokens),
                        .string(RunLogFormat.cost(s.exact)), .string(s.estimated > 0 ? "≈" + RunLogFormat.cost(s.estimated) : "0")]
            }
            return out.emit(.object([("usage", .table(["period", "runs", "tokens_in", "tokens_out", "cost", "speech_estimate"],
                                                      [summary("today", nil), summary("7 days", 7 * 86_400), summary("30 days", 30 * 86_400)]))]),
                            help: ["vp history show <n>   (one run's log and cost)"])
        }
        var shown = Array(records.enumerated())
        if let track = parsed["track"]?.lowercased() {
            shown = shown.filter { ConfigFile.slug($0.element.trackName) == track || $0.element.trackName.lowercased() == track }
        }
        if let search = parsed["search"] {
            shown = shown.filter { $0.element.text.localizedCaseInsensitiveContains(search) || ($0.element.heard?.localizedCaseInsensitiveContains(search) ?? false) }
        }
        if let since = parsed["since"] {
            guard let seconds = durationSeconds(since) else { throw UsageError("bad_value", "--since takes 30m, 2h, 3d…") }
            shown = shown.filter { Date().timeIntervalSince($0.element.date) <= seconds }
        }
        let limit = try parsed.int("limit") ?? 10
        let matching = shown.count
        shown = Array(shown.prefix(limit))
        out.emit(.object([
            ("count", .string("\(shown.count) of \(matching) matching (\(records.count) total)")),
            ("runs", .table(["n", "at", "track", "ms", "cost", "text"], shown.map { index, r in
                [.int(index + 1), .string(r.date.shortAgo), .string(r.trackName), .int(r.totalMs),
                 .string(r.log == nil ? "" : UsageSummary([r]).usedCloud ? RunLogFormat.cost(UsageSummary([r]).exact + UsageSummary([r]).estimated) : "local"),
                 .string(out.trim(r.text, 100) + (r.failure.map { " · failed: \($0)" } ?? ""))]
            })),
        ]), help: shown.isEmpty ? ["vp run <id> --text \"…\""] : ["vp history show <n>   (the run's log: every step, Jev's picks, tokens, cost)", "vp history usage   (today, 7 and 30 days)"])
    }

    static func durationSeconds(_ text: String) -> TimeInterval? {
        guard let unit = text.last, let value = Double(text.dropLast()) else { return nil }
        switch unit {
        case "s": return value
        case "m": return value * 60
        case "h": return value * 3600
        case "d": return value * 86_400
        default: return nil
        }
    }

    // MARK: Vocabulary

    static func vocab(_ parsed: Parsed, _ out: Output) throws {
        let url = ConfigPaths.vocabulary
        let text: String
        switch DiskText.read(url) {
        case .text(let t): text = t
        case .missing: text = VocabularyFile.write(VocabularyStore.starters)
        case .unreadable:
            throw AppClient.Failure(code: "vocabulary_unreadable", message: "vocabulary.toml isn't readable as UTF-8 text.",
                                    hint: "fix or remove \(ConfigPaths.tilde(url)), then vp vocab")
        }
        let result = VocabularyFile.parse(text)
        guard var entries = result.entries else {
            throw AppClient.Failure(code: "vocabulary_invalid", message: "vocabulary.toml doesn't check out: \(result.errors.first?.description ?? "")",
                                    hint: "fix \(ConfigPaths.tilde(url)), then vp vocab")
        }
        func save() throws {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            ConfigBackups.save(text, of: url)
            try writeConfigText(VocabularyFile.write(entries), to: url)
        }
        switch parsed.positionals.first {
        case nil, "list":
            out.emit(.object([("count", .int(entries.count)),
                              ("words", .table(["write", "heard_as", "exact"], entries.map { [.string($0.write), .string($0.heardAs.joined(separator: ", ")), .bool($0.alwaysExact)] }))]),
                     help: ["vp vocab add \"<word>\" --heard \"<mishearing>, <another>\"", "vp vocab test \"<sentence>\""])
        case "add":
            let word = try parsed.positional(1, "word", usage: "vp vocab add <word> --heard \"a, b\"")
            let heard = (parsed["heard"] ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if let i = entries.firstIndex(where: { $0.write.lowercased() == word.lowercased() }) {
                let merged = entries[i].heardAs + heard.filter { h in !entries[i].heardAs.contains { $0.lowercased() == h.lowercased() } }
                let changed = merged != entries[i].heardAs || (parsed.has("exact") && !entries[i].alwaysExact)
                entries[i].heardAs = merged
                if parsed.has("exact") { entries[i].alwaysExact = true }
                if changed { try save() }
                out.emit(.object([("word", .string(word)), ("heard_as", .list(merged.map(Out.string))), ("added", .bool(false)), ("changed", .bool(changed))]))
            } else {
                entries.append(VocabularyEntry(write: word, heardAs: heard, alwaysExact: parsed.has("exact")))
                try save()
                out.emit(.object([("word", .string(word)), ("heard_as", .list(heard.map(Out.string))), ("added", .bool(true))]),
                         help: ["vp vocab train \"\(word)\"   (collect its mishearings by voice)"])
            }
        case "remove":
            let word = try parsed.positional(1, "word", usage: "vp vocab remove <word>")
            let before = entries.count
            entries.removeAll { $0.write.lowercased() == word.lowercased() }
            if entries.count != before { try save() }
            out.emit(.object([("word", .string(word)), ("removed", .bool(entries.count != before))]))
        case "test":
            let sentence = parsed.positionals.dropFirst().joined(separator: " ")
            guard !sentence.isEmpty else { throw UsageError("missing_text", "Give a sentence.", hint: "vp vocab test \"i use cloud code\"") }
            out.emit(.object([("input", .string(sentence)), ("output", .string(FixWords.apply(sentence, entries: entries)))]))
        case "train":
            let word = try parsed.positional(1, "word", usage: "vp vocab train <word>")
            out.emit(Out(any: try AppClient.request("vocab.train", ["word": word])),
                     help: ["Say the word a few times in the window that opened, then Train"])
        default:
            throw UsageError("unknown_subcommand", "vp vocab takes list, add, remove, test or train.", hint: "vp vocab --help")
        }
    }

    // MARK: Config

    static func config(_ parsed: Parsed, _ out: Output) throws {
        switch parsed.positionals.first {
        case nil, "show":
            let (config, issues) = loadConfig()
            out.emit(.object([
                ("path", .string(ConfigPaths.tilde(ConfigPaths.config))),
                ("vocabulary", .string(ConfigPaths.tilde(ConfigPaths.vocabulary))),
                ("schema", .string(ConfigPaths.tilde(ConfigPaths.directory.appendingPathComponent("config.schema.json")))),
                ("health", .string(issueSummary(issues))),
                ("appearance", .string(config?.appearance.rawValue ?? "?")),
                ("microphone", .string(config?.microphone.rawValue ?? "?")),
                ("tracks", .int(config?.tracks.count ?? 0)),
            ]), help: ["vp config check", "vp help config   (the block reference)", "vp config backups"])
        case "path":
            print(ConfigPaths.config.path)
        case "check":
            let url = parsed.positionals.count > 1 ? URL(fileURLWithPath: parsed.positionals[1]) : ConfigPaths.config
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                throw AppClient.Failure(code: "no_such_file", message: "Can't read \(url.path).", hint: "vp config path")
            }
            let isVocabulary = url.lastPathComponent.hasPrefix("vocabulary")
            let (errors, warnings): ([ConfigIssue], [ConfigIssue])
            if isVocabulary {
                let r = VocabularyFile.parse(text)
                (errors, warnings) = (r.errors, r.warnings)
            } else {
                let r = ConfigFile.parse(text)
                (errors, warnings) = (r.errors, r.warnings)
            }
            let issues = errors + warnings
            out.emit(.object([
                ("file", .string(ConfigPaths.tilde(url))),
                ("result", .string(errors.isEmpty ? (warnings.isEmpty ? "ok" : "ok with warnings") : "not valid: the app keeps the last good version")),
                ("issues", .table(["severity", "line", "where", "problem"], issues.map {
                    [.string($0.severity.rawValue), $0.line.map(Out.int) ?? .null, .string($0.path), .string($0.message)]
                })),
            ]), help: errors.isEmpty ? [] : ["fix the file, then vp config check again", "vp config backups   (restore a good version)"])
            if !errors.isEmpty { exit(1) }
        case "schema":
            print(parsed.positionals.dropFirst().first == "vocabulary" ? ConfigSchema.vocabulary : ConfigSchema.config)
        case "backups":
            let list = ConfigBackups.list(of: ConfigPaths.config) + ConfigBackups.list(of: ConfigPaths.vocabulary)
            let sorted = list.sorted { $0.date > $1.date }
            out.emit(.object([("count", .int(sorted.count)), ("backups", .table(["n", "file", "saved"], sorted.enumerated().map { i, b in
                [.int(i + 1), .string(b.url.lastPathComponent), .string(b.date.shortAgo)]
            }))]), help: sorted.isEmpty ? [] : ["vp config restore <n>"])
        case "restore":
            let n = Int(try parsed.positional(1, "n", usage: "vp config restore <n>")) ?? 0
            let sorted = (ConfigBackups.list(of: ConfigPaths.config) + ConfigBackups.list(of: ConfigPaths.vocabulary)).sorted { $0.date > $1.date }
            guard n >= 1, n <= sorted.count else { throw AppClient.Failure(code: "no_such_backup", message: "There are \(sorted.count) backups.", hint: "vp config backups") }
            let backup = sorted[n - 1]
            let target = backup.url.lastPathComponent.hasPrefix("vocabulary") ? ConfigPaths.vocabulary : ConfigPaths.config
            ConfigBackups.beforeWrite(target, ours: nil, broken: true, in: ConfigPaths.backups)
            try writeConfigText(String(contentsOf: backup.url, encoding: .utf8), to: target)
            out.emit(.object([("restored", .string(backup.url.lastPathComponent)), ("to", .string(ConfigPaths.tilde(target)))]),
                     help: ["vp config check"])
        case "reload":
            out.emit(Out(any: try AppClient.request("config.reload")))
        case "open":
            NSWorkspace.shared.open(ConfigPaths.config)
            out.emit(.object([("opened", .string(ConfigPaths.tilde(ConfigPaths.config)))]))
        default:
            throw UsageError("unknown_subcommand", "vp config takes show, check, schema, backups, restore, reload, open or path.", hint: "vp config --help")
        }
    }

    // MARK: Models and voices

    static func models(_ parsed: Parsed, _ out: Output) throws {
        let capability = parsed["capability"] ?? "text"
        guard ["text", "transcription", "speech"].contains(capability) else { throw UsageError("bad_value", "--capability is text, transcription or speech.") }
        let data = try AppClient.request("models", ["capability": capability])
        var list = data["models"] as? [[String: Any]] ?? []
        if let search = parsed["search"]?.lowercased() {
            list = list.filter { "\($0["id"] ?? "") \($0["name"] ?? "")".lowercased().contains(search) }
        }
        let limit = try parsed.int("limit") ?? 20
        out.emit(.object([
            ("count", .string("\(min(limit, list.count)) of \(list.count)")),
            ("models", .table(["id", "name", "price"], list.prefix(limit).map { [.string($0["id"] as? String ?? ""), .string($0["name"] as? String ?? ""), .string($0["price"] as? String ?? "")] })),
            ("on_this_mac", .string(capability == "transcription" ? "parakeet" : capability == "speech" ? "pocket, supertonic, macos" : "none")),
        ]), help: ["vp models --capability \(capability) --search <text>"])
    }

    static func voices(_ parsed: Parsed, _ out: Output) throws {
        let model = parsed["model"] ?? "pocket"
        let list: [[String: Any]]
        if model == "pocket" || model == "supertonic" {
            let engine: LocalVoiceEngine = model == "pocket" ? .pocket : .supertonic
            list = engine.voices.map { ["id": $0, "name": engine.voiceLabel($0), "default": $0 == engine.defaultVoice] }
        } else {
            list = (try AppClient.request("voices", ["model": model]))["voices"] as? [[String: Any]] ?? []
        }
        out.emit(.object([("model", .string(model)), ("count", .int(list.count)),
                          ("voices", .table(["id", "name", "default"], list.map { [.string($0["id"] as? String ?? ""), .string($0["name"] as? String ?? ""), .bool($0["default"] as? Bool ?? false)] }))]),
                 help: ["vp say \"Hello\" --model \(model) --voice <id>"])
    }

    // MARK: Keys

    static func auth(_ parsed: Parsed, _ out: Output) throws {
        func providers(_ data: [String: Any]) -> Out {
            let list = data["providers"] as? [[String: Any]] ?? [data]
            return .table(["provider", "set", "key", "used_for"], list.map {
                [.string($0["id"] as? String ?? ""), .bool($0["set"] as? Bool ?? false), .s($0["key"] as? String), .string($0["used_for"] as? String ?? "")]
            })
        }
        switch parsed.positionals.first {
        case nil, "status":
            out.emit(.object([("providers", providers(try AppClient.request("auth.status")))]),
                     help: ["vp auth login openrouter", "vp auth set typesafe --key <key>   (or pipe it in)"])
        case "login":
            let provider = try parsed.positional(1, "provider", usage: "vp auth login openrouter")
            var args: [String: Any] = ["provider": provider, "headless": parsed.has("headless")]
            if let code = parsed["code"] { args["code"] = code }
            if !parsed.has("headless"), parsed["code"] == nil, !out.json { print("Opening your browser to sign in to OpenRouter…"); fflush(stdout) }
            var url: String?
            let data = try AppClient.request("auth.login", args) { event in url = event["url"] as? String }
            if data["pending"] as? Bool == true {
                out.emit(.object([("open", .string(url ?? "")), ("then", .string("OpenRouter shows a code"))]),
                         help: ["vp auth login openrouter --code <code>   (within 10 minutes)"])
            } else {
                out.emit(.object([("providers", providers(data))]), help: ["vp status"])
            }
        case "set":
            let provider = try parsed.positional(1, "provider", usage: "vp auth set <provider> --key <key>")
            guard let key = parsed["key"] ?? textArgument(Parsed.empty, from: 0) else {
                throw UsageError("missing_key", "No key.", hint: "echo \"$KEY\" | vp auth set \(provider)   or   --key <key>")
            }
            out.emit(.object([("providers", providers(try AppClient.request("auth.set", ["provider": provider, "key": key])))]))
        case "remove":
            let provider = try parsed.positional(1, "provider", usage: "vp auth remove <provider>")
            out.emit(.object([("providers", providers(try AppClient.request("auth.remove", ["provider": provider])))]))
        default:
            throw UsageError("unknown_subcommand", "vp auth takes status, login, set or remove.", hint: "vp auth --help")
        }
    }

    static func secret(_ parsed: Parsed, _ out: Output) throws {
        switch parsed.positionals.first {
        case nil, "list":
            let names = (try AppClient.request("secret.list"))["secrets"] as? [String] ?? []
            out.emit(.object([("count", .int(names.count)), ("secrets", .list(names.map(Out.string)))]),
                     help: ["vp secret set <name> --value <v>   (or pipe it in); use ${secret:<name>} in an http block"])
        case "set":
            let name = try parsed.positional(1, "name", usage: "vp secret set <name> --value <v>")
            guard let value = parsed["value"] ?? textArgument(Parsed.empty, from: 0) else {
                throw UsageError("missing_value", "No value.", hint: "echo \"$TOKEN\" | vp secret set \(name)")
            }
            out.emit(Out(any: try AppClient.request("secret.set", ["name": name, "value": value])),
                     help: ["use \"${secret:\(name)}\" in an http block's url, headers or body"])
        case "remove":
            let name = try parsed.positional(1, "name", usage: "vp secret remove <name>")
            out.emit(Out(any: try AppClient.request("secret.remove", ["name": name])))
        default:
            throw UsageError("unknown_subcommand", "vp secret takes list, set or remove.", hint: "vp secret --help")
        }
    }

    // MARK: Reading keys

    /// [settings.reading] from the command line (the app picks the change up within a second).
    static func reading(_ parsed: Parsed, _ out: Output) throws {
        let (loaded, issues) = loadConfig()
        guard var config = loaded else {
            throw AppClient.Failure(code: "config_invalid", message: "config.toml doesn't check out: \(issues.first?.description ?? "")", hint: "vp config check")
        }
        let actions = ReadingSettings.Action.allCases.map(\.rawValue)
        func action(_ index: Int) throws -> ReadingSettings.Action {
            let name = try parsed.positional(index, "action", usage: "vp reading key <action> <key>…")
            guard let action = ReadingSettings.Action(rawValue: name) else {
                throw UsageError("bad_value", "No action '\(name)'.\(TableReader.suggestion(name, actions))", hint: "actions: " + actions.joined(separator: ", "))
            }
            return action
        }
        func combo(_ name: String) throws -> KeyCombo {
            do { return try KeyNames.parse(name) } catch { throw UsageError("bad_value", "'\(name)' \(error)") }
        }
        switch parsed.positionals.first {
        case nil:
            break
        case "keys":
            let mode = try parsed.positional(1, "mode", usage: "vp reading keys always|hover|click|never")
            guard let value = ReadingSettings.TakeKeys(rawValue: mode) else {
                throw UsageError("bad_value", "keys is always, hover, click or never.\(TableReader.suggestion(mode, ReadingSettings.TakeKeys.allCases.map(\.rawValue)))")
            }
            config.reading.takeKeys = value
        case "click-away":
            let mode = try parsed.positional(1, "mode", usage: "vp reading click-away keep-reading|stop")
            guard let value = ReadingSettings.ClickAway(rawValue: mode) else { throw UsageError("bad_value", "click-away is keep-reading or stop.") }
            config.reading.clickAway = value
        case "key":
            let which = try action(1)
            let names = Array(parsed.positionals.dropFirst(2))
            guard !names.isEmpty else { throw UsageError("missing_value", "Which keys?", hint: "vp reading key faster period shift+equal") }
            config.reading.keys[which] = try names.map(combo)
        case "shortcut":
            let which = try action(1)
            let name = try parsed.positional(2, "combo", usage: "vp reading shortcut faster control+option+right   (or none)")
            if name == "none" {
                config.reading.global[which] = nil
            } else {
                let parsedCombo = try combo(name)
                guard !parsedCombo.modifiers.isEmpty else { throw UsageError("bad_value", "A shortcut that works in any app needs control, option or command.") }
                config.reading.global[which] = parsedCombo
            }
        case "reset":
            config.reading = ReadingSettings()
        default:
            throw UsageError("unknown_subcommand", "vp reading takes keys, click-away, key, shortcut or reset.", hint: "vp reading --help")
        }
        if parsed.positionals.first != nil { try writeConfig(config) }
        let r = config.reading
        out.emit(.object([
            ("keys", .string(r.takeKeys.rawValue)), ("click_away", .string(r.clickAway.rawValue)),
            ("bindings", .table(["action", "keys", "anywhere"], ReadingSettings.Action.allCases.map { a in
                [.string(a.rawValue), .string((r.keys[a] ?? []).map(KeyNames.format).joined(separator: " ")),
                 .string(r.global[a].map(KeyNames.format) ?? "")]
            })),
        ]), help: ["vp reading keys always|hover|click|never", "vp reading key faster period shift+equal", "vp reading shortcut faster control+option+right"])
    }

    // MARK: Windows

    static func open(_ parsed: Parsed, _ out: Output) throws {
        let target = parsed.positionals.first ?? "main"
        var args: [String: Any] = ["target": target]
        if target == "track" { args["track"] = try parsed.positional(1, "id", usage: "vp open track <id> [--step n]") }
        for name in ["step", "route", "section", "search", "run", "word", "field"] { if let value = parsed[name] { args[name] = value } }
        if let track = parsed["track"] { args["track"] = track }
        for name in ["add", "background"] where parsed.has(name) { args[name] = true }
        try uiReply("open", args, out)
    }

    /// open / close / ui answer with the screen's state; the hints say what else can be shown from here.
    static func uiReply(_ command: String, _ args: [String: Any], _ out: Output) throws {
        let state = try AppClient.request(command, args)
        var help: [String] = []
        switch state["page"] as? String {
        case "track":
            let id = state["track"] as? String ?? "<id>"
            help = state["step"] is Int
                ? ["vp open track \(id) --step <n> --field <name>   (focus a block's field)", "vp close main"]
                : ["vp open track \(id) --step <n>   (open a block)", "vp open track \(id) --field name"]
        case "history": help = ["vp open history --track <id> --search \"…\"", "vp open history --run <n>   (n from vp history)"]
        case "vocabulary": help = ["vp open vocabulary --word \"<w>\"", "vp vocab train \"<w>\""]
        case "setup": help = ["vp open setup --section " + SetupView.sections.joined(separator: "|")]
        default: help = ["vp open track <id>", "vp open menu"]
        }
        out.emit(Out(any: state), help: help)
    }

    // MARK: Config files (offline)

    static func loadConfig() -> (AppConfig?, [ConfigIssue]) {
        guard let text = try? String(contentsOf: ConfigPaths.config, encoding: .utf8) else {
            return (nil, [ConfigIssue(severity: .error, path: "", message: "no config.toml yet (the app writes it on first launch)")])
        }
        let result = ConfigFile.parse(text)
        return (result.config, result.errors + result.warnings)
    }

    static func writeConfig(_ config: AppConfig) throws {
        let url = ConfigPaths.config
        ConfigBackups.beforeWrite(url, ours: nil, broken: true, in: ConfigPaths.backups)
        try writeConfigText(ConfigFile.write(config), to: url)
    }

    static func issueSummary(_ issues: [ConfigIssue]) -> String {
        let errors = issues.filter { $0.severity == .error }.count, warnings = issues.count - errors
        if errors > 0 { return "\(errors) error\(errors == 1 ? "" : "s"): not applied (vp config check)" }
        return warnings > 0 ? "ok, \(warnings) warning\(warnings == 1 ? "" : "s")" : "ok"
    }

    // MARK: Help

    static func help(_ topics: [String], _ out: Output) {
        if topics.first == "config" { print(ConfigFile.reference); return }
        if let name = topics.first, let spec = table.first(where: { $0.name == name }) {
            var pairs: [(String, Out)] = [("usage", .string(spec.usage)), ("does", .string(spec.summary))]
            if !(spec.values + spec.switches).isEmpty { pairs.append(("flags", .list((spec.values.map { "--\($0) <value>" } + spec.switches.map { "--\($0)" }).map(Out.string)))) }
            pairs.append(("global", .string("--json (JSON instead of TOON) · --full (no truncation) · --help")))
            return out.emit(.object(pairs))
        }
        out.emit(.object([
            ("description", .string(CLI.description)),
            ("commands", .table(["command", "does"], table.map { [.string($0.usage), .string($0.summary)] })),
            ("config", .string("\(ConfigPaths.tilde(ConfigPaths.config)) · vp help config prints the block reference")),
            ("output", .string("TOON by default, --json for JSON; errors on stdout; exit 0 ok, 1 error, 2 usage")),
        ]), help: ["vp   (home: live state)", "vp <command> --help"])
    }
}

extension Parsed {
    static let empty = try! Parsed([], spec: CommandSpec(name: "", usage: "", summary: "", handler: { _, _ in }))
}
