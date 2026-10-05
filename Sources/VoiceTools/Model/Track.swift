import Foundation

/// A track is a named pipeline: one or more triggers start it, and its steps run in order,
/// each step consuming the previous step's output.
struct Track: Codable, Identifiable, Hashable {
    var id = UUID()
    /// The track's stable name in config.toml and the CLI (`fast-dictation`). Nil in tracks saved before 1.6.0;
    /// derived from the name then.
    var slug: String?
    var name: String
    var colorHex: String
    var enabled = true
    var triggers: [Trigger]
    var steps: [Step]
}

struct Trigger: Codable, Identifiable, Hashable {
    enum Mode: String, Codable, CaseIterable {
        /// Press to start, press again to stop (or pause/resume while speaking).
        case toggle
        /// Runs while held; releasing ends capture.
        case hold
        /// Each press runs the track once from the start: a microphone track records until you pause (or press
        /// again); a text track starts over (pressing while it reads stops that and reads again).
        case once

        var label: String {
            switch self {
            case .toggle: "Toggle"
            case .hold: "Press & hold"
            case .once: "Once"
            }
        }
    }

    var id = UUID()
    var combo: KeyCombo
    var mode: Mode
}

/// What flows between steps.
enum DataKind: String, Codable {
    case none
    case audio
    case text
}

struct Step: Codable, Identifiable, Hashable {
    var id = UUID()
    var kind: StepKind
}

enum TextSource: String, Codable, CaseIterable, Identifiable {
    case selection
    case page
    case clipboard
    case previousClipboard

    var id: String { rawValue }

    var label: String {
        switch self {
        case .selection: "Selected text"
        case .page: "Current page"
        case .clipboard: "Clipboard"
        case .previousClipboard: "Previous clipboard"
        }
    }
}

/// How the on-device Parakeet step handles a live recording.
enum ParakeetMode: String, Codable, CaseIterable, Identifiable {
    /// Transcribe the whole recording on release. Most accurate; still ~0.2 s for 20 s of speech.
    case onRelease
    /// Transcribe each phrase at natural pauses while recording; release only waits for the last phrase.
    case pauseChunks
    /// Sliding-window streaming with overlapping context; live text while you talk.
    case streaming

    var id: String { rawValue }

    var label: String {
        switch self {
        case .onRelease: "On release (most accurate)"
        case .pauseChunks: "Chunk at pauses"
        case .streaming: "Streaming (live text)"
        }
    }

    var detail: String {
        switch self {
        case .onRelease: "Transcribes the whole recording when you stop. Parakeet does ~20 s of speech in about 0.2 s."
        case .pauseChunks: "Transcribes each phrase when you pause, so long dictations finish sooner. Each phrase is decoded on its own, so accuracy can drop at the cuts."
        case .streaming: "Transcribes in overlapping windows as you talk and shows live text. Release waits for the last window (up to ~11 s of audio)."
        }
    }
}

enum FailurePolicy: String, Codable, CaseIterable {
    case passThrough
    case stop
}

/// One branch of a Route step: Jev picks the route whose `when` fits the input best, then `model` answers with
/// `prompt` (the same way an LLM step does).
struct Route: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var when: String
    var model: String
    var prompt: String
}

enum StepKind: Codable, Hashable {
    // Inputs
    /// `input`: a mic's name or `AudioInputs.system`; nil = the app's input (Setup → Microphone). Optional so tracks
    /// saved before 1.10.0 still load.
    case microphone(input: String?)
    case text(sources: [TextSource])

    // Transcribe (audio -> text)
    /// `mode` is optional so tracks saved before it existed still load (nil = on release).
    case parakeet(chunkOnPauseMs: Int, mode: ParakeetMode?)
    case openRouterSTT(model: String)

    // Transform (text -> text)
    case llm(model: String, prompt: String, onFailure: FailurePolicy)
    /// Jev chooses one of the routes for the input; that route's model and instructions produce the output.
    case route(routes: [Route])
    /// Jev answers `question` about the text and picks a branch; that branch's own steps run, then the track
    /// carries on with what it produced. A branch with no steps passes the text through.
    case branch(question: String?, branches: [Branch])
    case http(url: String, method: String, headers: [String: String], bodyTemplate: String, responseField: String)
    case template(String)
    /// Find-and-replace from the shared vocabulary (Voice Pipes → Vocabulary).
    case fixWords

    // Outputs
    case paste(restoreClipboard: Bool)
    case copy
    case speak(voiceID: String?, rate: Float)
    case openRouterSpeech(model: String, voice: String, rate: Float)
    case localSpeech(engine: LocalVoiceEngine, voice: String, rate: Float)
    case showHUD

    var isMicrophone: Bool { if case .microphone = self { true } else { false } }

    var input: DataKind {
        switch self {
        case .microphone, .text: .none
        case .parakeet, .openRouterSTT: .audio
        case .llm, .route, .branch, .http, .template, .fixWords, .paste, .copy, .speak, .openRouterSpeech, .localSpeech, .showHUD: .text
        }
    }

    var output: DataKind {
        switch self {
        case .microphone: .audio
        case .text, .parakeet, .openRouterSTT, .llm, .route, .http, .template, .fixWords: .text
        // Outputs pass their text through so a track can, e.g., paste and then POST.
        case .paste, .copy, .showHUD: .text
        case .speak, .openRouterSpeech, .localSpeech: .none
        // What every branch ends with (text if a branch has no steps); `none` when they differ.
        case .branch(_, let branches):
            Set(branches.map { $0.steps.last?.kind.output ?? .text }).count == 1
                ? branches.first?.steps.last?.kind.output ?? .text : .none
        }
    }

    var category: String {
        switch self {
        case .microphone, .text: "Input"
        case .parakeet, .openRouterSTT: "Transcribe"
        case .llm, .route, .branch, .http, .template, .fixWords: "Transform"
        case .paste, .copy, .speak, .openRouterSpeech, .localSpeech, .showHUD: "Output"
        }
    }

    var title: String {
        switch self {
        case .microphone: "Microphone"
        case .text(let sources): sources.map(\.label).joined(separator: " → ")
        case .parakeet(_, let mode):
            switch mode ?? .onRelease {
            case .onRelease: "Parakeet v3"
            case .pauseChunks: "Parakeet v3 · chunked"
            case .streaming: "Parakeet v3 · streaming"
            }
        case .openRouterSTT(let model): model
        case .llm(let model, _, _): "LLM · \(model)"
        case .route(let routes): "Route · Jev · " + routes.map(\.name).joined(separator: " / ")
        case .branch(_, let branches): "Branch · Jev · " + branches.map(\.name).joined(separator: " / ")
        case .http(let url, let method, _, _, _): "\(method) \(URL(string: url)?.host ?? url)"
        case .template: "Text template"
        case .fixWords: "Fix words"
        case .paste: "Paste at cursor"
        case .copy: "Copy to clipboard"
        case .speak: "Speak · macOS voice"
        case .localSpeech(let engine, let voice, _): "Speak · \(engine.label) · \(engine.voiceLabel(voice))"
        case .openRouterSpeech(let model, let voice, _):
            "Speak · \(model.split(separator: "/").last ?? "") · \(OpenRouterCatalog.Model.voiceLabel(voice))"
        case .showHUD: "Show in HUD"
        }
    }

    /// Short label for the menu bar chips.
    var chip: String {
        switch self {
        case .microphone: "Mic"
        case .text(let sources): sources.first?.label ?? "Text"
        case .parakeet: "Parakeet"
        case .openRouterSTT(let model): model.split(separator: "/").last.map(String.init) ?? model
        case .llm(let model, _, _): model.split(separator: "/").last.map(String.init) ?? model
        case .route: "Jev route"
        case .branch: "Jev branch"
        case .http(_, let method, _, _, _): method
        case .template: "Template"
        case .fixWords: "Fix words"
        case .paste: "Paste"
        case .copy: "Copy"
        case .speak: "Speak"
        case .localSpeech(let engine, let voice, _): "Speak · \(engine.voiceLabel(voice))"
        case .openRouterSpeech(_, let voice, _): "Speak · \(OpenRouterCatalog.Model.voiceLabel(voice).components(separatedBy: " (").first ?? voice)"
        case .showHUD: "HUD"
        }
    }

    static let defaultSpeechModel = "microsoft/mai-voice-2.1"
    static let defaultSpeechVoice = "en-US-Harper:MAI-Voice-2.1"

    /// The block's name in the "Add step" menu: one Transcribe and one Speak block, whose model is picked inside.
    var blockTitle: String {
        switch self {
        case .parakeet, .openRouterSTT: "Transcribe"
        case .speak, .openRouterSpeech, .localSpeech: "Speak"
        case .llm: "LLM · OpenRouter"
        case .route: "Route · Jev"
        case .branch: "Branch · Jev"
        default: title
        }
    }

    /// Catalog for the "Add step" menu.
    static let catalog: [StepKind] = [
        .microphone(input: nil),
        .text(sources: [.selection, .page, .clipboard]),
        .parakeet(chunkOnPauseMs: 500, mode: .onRelease),
        .llm(model: "anthropic/claude-haiku-4.5", prompt: "", onFailure: .passThrough),
        .route(routes: Route.answerRoutes),
        .branch(question: Branch.starterQuestion, branches: Branch.starters),
        .fixWords,
        .http(url: "https://", method: "POST", headers: ["Content-Type": "application/json"],
              bodyTemplate: #"{"text": {{input_json}}}"#, responseField: ""),
        .template("{{input}}"),
        .paste(restoreClipboard: true),
        .copy,
        .localSpeech(engine: .pocket, voice: LocalVoiceEngine.pocket.defaultVoice, rate: 1.0),
        .showHUD,
    ]
}

extension Track {
    /// Returns a description of the first type mismatch between adjacent steps, if any.
    var validationError: String? {
        guard let first = steps.first else { return "Add at least one step." }
        if first.kind.input != .none { return "The first step must be an input." }
        return Self.chainError(steps)
    }

    /// Type checks a run of steps (a track's, or a branch's, which starts from text), branches included.
    static func chainError(_ steps: [Step], from input: DataKind? = nil) -> String? {
        if let input, let first = steps.first, first.kind.input != input {
            return "\(first.kind.title) needs \(first.kind.input.rawValue), but the branch gets \(input.rawValue)."
        }
        for (i, step) in steps.enumerated() {
            switch step.kind {
            case .route(let routes) where routes.isEmpty:
                return "Route · Jev needs at least one route."
            case .branch(_, let branches):
                if branches.isEmpty { return "Branch · Jev needs at least one branch." }
                for branch in branches {
                    if let input = branch.steps.first(where: { $0.kind.input == .none }) {
                        return "\(branch.name): \(input.kind.blockTitle) can only start a track, not a branch."
                    }
                    if let error = chainError(branch.steps, from: .text) { return "\(branch.name): \(error)" }
                }
                if i < steps.count - 1, Set(branches.map { $0.steps.last?.kind.output ?? .text }).count > 1 {
                    return "The branches end differently (some speak, some give text), so nothing can follow them: put the next steps inside each branch."
                }
            default:
                break
            }
        }
        for (a, b) in zip(steps, steps.dropFirst()) where a.kind.output != b.kind.input {
            return "\(b.kind.title) needs \(b.kind.input.rawValue), but \(a.kind.title) produces \(a.kind.output.rawValue)."
        }
        return nil
    }

    static let cleanupPrompt = """
        Rewrite this dictated text as clean written prose. Remove filler words and false starts, \
        fix punctuation and capitalization, and keep the speaker's wording and meaning. \
        Return only the rewritten text.
        """

    static let defaults: [Track] = [
        Track(name: "Fast dictation", colorHex: "#F0A35E",
              triggers: [Trigger(combo: KeyCombo(key: .space, modifiers: [.option]), mode: .hold)],
              steps: [Step(kind: .microphone(input: nil)), Step(kind: .parakeet(chunkOnPauseMs: 500, mode: .onRelease)),
                      Step(kind: .fixWords), Step(kind: .paste(restoreClipboard: true))]),
        Track(name: "Clean dictation", colorHex: "#8FB8D6",
              triggers: [Trigger(combo: KeyCombo(key: .space, modifiers: [.option, .shift]), mode: .toggle)],
              steps: [Step(kind: .microphone(input: nil)), Step(kind: .openRouterSTT(model: "microsoft/mai-transcribe-2")), Step(kind: .fixWords),
                      Step(kind: .llm(model: "anthropic/claude-haiku-4.5", prompt: cleanupPrompt, onFailure: .passThrough)),
                      Step(kind: .paste(restoreClipboard: true))]),
        Track(name: "Read aloud", colorHex: "#C3A3D4",
              triggers: [Trigger(combo: KeyCombo(key: .r, modifiers: [.option]), mode: .toggle)],
              steps: [Step(kind: .text(sources: [.selection, .page, .clipboard])),
                      Step(kind: .branch(question: Branch.starterQuestion, branches: Branch.starters)),
                      Step(kind: .localSpeech(engine: .pocket, voice: LocalVoiceEngine.pocket.defaultVoice, rate: 1.0))]),
        quickAnswer,
    ]

    /// Ask out loud, hear a short answer (1.15.0). Jev routes each question to a quick, web or deep model; without a
    /// Jev key the first route (quick: Claude Haiku) answers, so it works with only an OpenRouter key. Pocket speaks it
    /// on this Mac. ⌥ Q: next to the other starters' ⌥ keys, and Q for quick.
    static let quickAnswer = Track(name: "Quick answer", colorHex: "#A9BF8A",
                                   triggers: [Trigger(combo: KeyCombo(key: .q, modifiers: [.option]), mode: .hold)],
                                   steps: [Step(kind: .microphone(input: nil)), Step(kind: .parakeet(chunkOnPauseMs: 500, mode: .onRelease)),
                                           Step(kind: .route(routes: Route.answerRoutes)),
                                           Step(kind: .localSpeech(engine: .pocket, voice: LocalVoiceEngine.pocket.defaultVoice, rate: 1.0))])
}

/// One way through a Branch block: what Jev chooses it by, and the steps it runs.
struct Branch: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var when: String
    var steps: [Step]

    static let starterQuestion = "How hard is this text for a text-to-speech voice to read aloud correctly?"

    static let speakablePrompt = """
        Rewrite the text so a text-to-speech voice reads it naturally. Spell out symbols, currency, percentages, \
        units, dates, times and abbreviations as spoken words. Keep the wording and meaning otherwise. Output only \
        the rewritten text.
        """

    static let describePrompt = """
        Rewrite the text so it can be read aloud and understood by ear. Spell out symbols, numbers, units, dates and \
        abbreviations as spoken words; say commands, file paths and URLs the way a person would say them (or name \
        them briefly when long); turn markdown, lists and tables into plain spoken sentences; describe code briefly \
        instead of reading it character by character. Keep the meaning. Output only the rewritten text.
        """

    /// Read aloud's starter: plain text as it is; some figures rewritten by a fast model; technical text rewritten
    /// by a stronger one. Jev decides in about 0.3 s (measured 8/8 on sample texts).
    static let starters: [Branch] = [
        Branch(name: "easy", when: "Plain prose: ordinary words and sentences that any voice reads correctly as written.", steps: []),
        Branch(name: "medium",
               when: "Mostly prose with a few things a voice may misread: some numbers, times, prices, dates, units or common abbreviations.",
               steps: [Step(kind: .llm(model: "google/gemini-2.5-flash-lite", prompt: speakablePrompt, onFailure: .passThrough))]),
        Branch(name: "hard",
               when: "Dense or technical: code, commands, file paths, URLs, markdown, lists or tables, or many figures, symbols and acronyms.",
               steps: [Step(kind: .llm(model: "anthropic/claude-haiku-4.5", prompt: describePrompt, onFailure: .passThrough))]),
    ]
}

extension Route {
    /// Starting routes for a spoken question: a fast model, a web-search model, a stronger model.
    static let answerRoutes: [Route] = [
        Route(name: "quick",
              when: "A short factual lookup, definition, conversion, spelling or yes/no that a small fast model answers well in a sentence or two.",
              model: "anthropic/claude-haiku-4.5",
              prompt: "Answer in one or two short sentences. The answer is read aloud: plain spoken language, no markdown, lists or links."),
        Route(name: "web",
              when: "Needs current or live information: news, prices, weather, sports results, today's events, anything that changes over time.",
              model: "perplexity/sonar",
              prompt: "Answer from current information in two or three sentences. The answer is read aloud: plain spoken language, no markdown, citations or links."),
        Route(name: "deep",
              when: "Needs reasoning, comparison, advice, planning or explaining a complex topic: a longer, considered answer.",
              model: "anthropic/claude-sonnet-5.5",
              prompt: "Give a thoughtful, well-reasoned answer in a short paragraph or two. The answer is read aloud: plain spoken language, no markdown, headings or bullet lists."),
    ]
}

/// Text-to-speech models that run on this Mac (through FluidAudio), no network needed after the first download.
enum LocalVoiceEngine: String, Codable, CaseIterable, Identifiable {
    /// Kyutai Pocket TTS: streams audio as it generates, so the first sound comes in ~25 ms.
    case pocket
    /// Supertonic-3: synthesizes a passage at ~80× real time; 31 languages.
    case supertonic

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pocket: "Pocket TTS"
        case .supertonic: "Supertonic-3"
        }
    }

    var detail: String {
        switch self {
        case .pocket:
            "Runs on this Mac and streams: the first sound starts in a few dozen milliseconds. About 770 MB, downloaded once. Kyutai's research model; check its license before commercial use."
        case .supertonic:
            "Runs on this Mac, about 80× faster than real time. About 100 MB, downloaded once; each voice is a small extra download."
        }
    }

    var voices: [String] {
        switch self {
        case .pocket:
            ["alba", "anna", "azelma", "bill_boerst", "caro_davy", "charles", "cosette", "eponine", "estelle", "eve",
             "fantine", "george", "giovanni", "jane", "javert", "jean", "juergen", "lola", "marius", "mary",
             "michael", "paul", "peter_yearsley", "rafael", "stuart_bell", "vera"]
        case .supertonic:
            ["F1", "F2", "F3", "F4", "F5", "M1", "M2", "M3", "M4", "M5"]
        }
    }

    var defaultVoice: String {
        switch self {
        case .pocket: "alba"
        case .supertonic: "F1"
        }
    }

    func voiceLabel(_ voice: String) -> String {
        switch self {
        case .pocket:
            voice.split(separator: "_").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
        case .supertonic:
            voice.hasPrefix("F") ? "Female \(voice.dropFirst())" : voice.hasPrefix("M") ? "Male \(voice.dropFirst())" : voice
        }
    }
}

extension Step {
    /// This step and, for a Branch, every step inside it (any depth).
    var flattened: [Step] {
        if case .branch(_, let branches) = kind { return [self] + branches.flatMap { $0.steps.flatMap(\.flattened) } }
        return [self]
    }
}

extension Track {
    /// Every step, including those inside branches: for checks such as "uses OpenRouter".
    var allSteps: [Step] { steps.flatMap(\.flattened) }
}

extension StepKind {
    /// The same settings with in-app identities (routes, branches, their steps) blanked: what the file stores.
    var normalized: StepKind {
        let blank = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        switch self {
        case .route(let routes):
            return .route(routes: routes.map { var r = $0; r.id = blank; return r })
        case .branch(let question, let branches):
            return .branch(question: question, branches: branches.map { branch in
                var b = branch
                b.id = blank
                b.steps = branch.steps.map { Step(id: blank, kind: $0.kind.normalized) }
                return b
            })
        default:
            return self
        }
    }

    /// A Route step's routes, else nil.
    var routes: [Route]? {
        if case .route(let routes) = self { routes } else { nil }
    }

    /// The case without its settings ("llm", "route", "copy"): two steps of the same block.
    var caseName: String {
        Mirror(reflecting: self).children.first?.label ?? String(describing: self)
    }

    /// Equal settings, ignoring the routes' in-app identities (which the config file doesn't carry).
    func sameSettings(as other: StepKind) -> Bool { normalized == other.normalized }
}

extension Track {
    /// What an outside edit (config.toml) changed in a track, for the open editor to point at.
    struct Changes {
        var steps: [Step.ID] = []
        var title = false
        var triggers = false
        var isEmpty: Bool { steps.isEmpty && !title && !triggers }
    }

    /// Takes over step, route and trigger identities from the version of this track before a reload (the file
    /// doesn't store them), so an open editor keeps its expanded step; returns what changed.
    mutating func adoptIdentities(from old: Track) -> Changes {
        var changes = Changes()
        changes.title = name != old.name || colorHex != old.colorHex || enabled != old.enabled
        var unused = old.steps
        var matched = Set<Int>()
        // Unchanged steps first, wherever they moved.
        for i in steps.indices {
            if let j = unused.firstIndex(where: { $0.kind.sameSettings(as: steps[i].kind) }) {
                adopt(old: unused.remove(at: j), into: i)
                matched.insert(i)
            }
        }
        // Then a changed step keeps the identity of the same block in the same place.
        for i in steps.indices where !matched.contains(i) {
            if old.steps.indices.contains(i), let j = unused.firstIndex(where: { $0.id == old.steps[i].id }),
               unused[j].kind.caseName == steps[i].kind.caseName {
                adopt(old: unused.remove(at: j), into: i)
            }
            changes.steps.append(steps[i].id)
        }
        var oldTriggers = old.triggers
        for i in triggers.indices {
            if let j = oldTriggers.firstIndex(where: { $0.combo == triggers[i].combo && $0.mode == triggers[i].mode }) {
                triggers[i].id = oldTriggers.remove(at: j).id
            } else {
                changes.triggers = true
            }
        }
        if !oldTriggers.isEmpty { changes.triggers = true }
        return changes
    }

    private mutating func adopt(old: Step, into i: Int) {
        steps[i] = Self.adopting(steps[i], from: old)
    }

    /// `step` with `old`'s identity, and its routes' and branches' (by name, else in order), branches' steps by
    /// position when they're the same block: an open editor keeps what it had open.
    private static func adopting(_ step: Step, from old: Step) -> Step {
        var step = step
        step.id = old.id
        switch (step.kind, old.kind) {
        case (.route(var routes), .route(let oldRoutes)):
            var unused = oldRoutes
            for r in routes.indices {
                let j = unused.firstIndex { $0.name == routes[r].name } ?? (unused.isEmpty ? nil : 0)
                if let j { routes[r].id = unused.remove(at: j).id }
            }
            step.kind = .route(routes: routes)
        case (.branch(let question, var branches), .branch(_, let oldBranches)):
            var unused = oldBranches
            for b in branches.indices {
                guard let j = unused.firstIndex(where: { $0.name == branches[b].name }) ?? (unused.isEmpty ? nil : 0) else { continue }
                let previous = unused.remove(at: j)
                branches[b].id = previous.id
                for k in branches[b].steps.indices where previous.steps.indices.contains(k)
                    && previous.steps[k].kind.caseName == branches[b].steps[k].kind.caseName {
                    branches[b].steps[k] = adopting(branches[b].steps[k], from: previous.steps[k])
                }
            }
            step.kind = .branch(question: question, branches: branches)
        default:
            break
        }
        return step
    }
}

// MARK: - Copies

extension Track {
    /// A copy with new identities throughout (track, triggers, steps, branches, routes), so editing it never touches
    /// the original. Disabled, so its hotkeys don't clash with the original's until you change them.
    func copied(named name: String) -> Track {
        var copy = self
        copy.id = UUID()
        copy.slug = nil
        copy.name = name
        copy.enabled = false
        copy.triggers = triggers.map { var t = $0; t.id = UUID(); return t }
        copy.steps = steps.map { $0.copied() }
        return copy
    }
}

extension Step {
    func copied() -> Step {
        var step = self
        step.id = UUID()
        switch kind {
        case .route(let routes):
            step.kind = .route(routes: routes.map { var r = $0; r.id = UUID(); return r })
        case .branch(let question, let branches):
            step.kind = .branch(question: question, branches: branches.map { b in
                var copy = b
                copy.id = UUID()
                copy.steps = b.steps.map { $0.copied() }
                return copy
            })
        default:
            break
        }
        return step
    }
}
