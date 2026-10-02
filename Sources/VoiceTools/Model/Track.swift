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
    case microphone
    case text(sources: [TextSource])

    // Transcribe (audio -> text)
    /// `mode` is optional so tracks saved before it existed still load (nil = on release).
    case parakeet(chunkOnPauseMs: Int, mode: ParakeetMode?)
    case openRouterSTT(model: String)

    // Transform (text -> text)
    case llm(model: String, prompt: String, onFailure: FailurePolicy)
    /// Jev chooses one of the routes for the input; that route's model and instructions produce the output.
    case route(routes: [Route])
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

    var input: DataKind {
        switch self {
        case .microphone, .text: .none
        case .parakeet, .openRouterSTT: .audio
        case .llm, .route, .http, .template, .fixWords, .paste, .copy, .speak, .openRouterSpeech, .localSpeech, .showHUD: .text
        }
    }

    var output: DataKind {
        switch self {
        case .microphone: .audio
        case .text, .parakeet, .openRouterSTT, .llm, .route, .http, .template, .fixWords: .text
        // Outputs pass their text through so a track can, e.g., paste and then POST.
        case .paste, .copy, .showHUD: .text
        case .speak, .openRouterSpeech, .localSpeech: .none
        }
    }

    var category: String {
        switch self {
        case .microphone, .text: "Input"
        case .parakeet, .openRouterSTT: "Transcribe"
        case .llm, .route, .http, .template, .fixWords: "Transform"
        case .paste, .copy, .speak, .openRouterSpeech, .localSpeech, .showHUD: "Output"
        }
    }

    var title: String {
        switch self {
        case .microphone: "Microphone"
        case .text(let sources): sources.map(\.label).joined(separator: " → ")
        case .parakeet(_, let mode):
            switch mode ?? .onRelease {
            case .onRelease: "Parakeet v3 · local"
            case .pauseChunks: "Parakeet v3 · chunked"
            case .streaming: "Parakeet v3 · streaming"
            }
        case .openRouterSTT(let model): model
        case .llm(let model, _, _): "LLM · \(model)"
        case .route(let routes): "Route · Jev · " + routes.map(\.name).joined(separator: " / ")
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
        default: title
        }
    }

    /// Catalog for the "Add step" menu.
    static let catalog: [StepKind] = [
        .microphone,
        .text(sources: [.selection, .page, .clipboard]),
        .parakeet(chunkOnPauseMs: 500, mode: .onRelease),
        .llm(model: "anthropic/claude-haiku-4.5", prompt: "", onFailure: .passThrough),
        .route(routes: Route.answerRoutes),
        .http(url: "https://", method: "POST", headers: ["Content-Type": "application/json"],
              bodyTemplate: #"{"text": {{input_json}}}"#, responseField: ""),
        .fixWords,
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
        for step in steps {
            if case .route(let routes) = step.kind, routes.isEmpty { return "Route · Jev needs at least one route." }
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
              steps: [Step(kind: .microphone), Step(kind: .parakeet(chunkOnPauseMs: 500, mode: .onRelease)),
                      Step(kind: .fixWords), Step(kind: .paste(restoreClipboard: true))]),
        Track(name: "Clean dictation", colorHex: "#8FB8D6",
              triggers: [Trigger(combo: KeyCombo(key: .space, modifiers: [.option, .shift]), mode: .toggle)],
              steps: [Step(kind: .microphone), Step(kind: .openRouterSTT(model: "microsoft/mai-transcribe-2")), Step(kind: .fixWords),
                      Step(kind: .llm(model: "anthropic/claude-haiku-4.5", prompt: cleanupPrompt, onFailure: .passThrough)),
                      Step(kind: .paste(restoreClipboard: true))]),
        Track(name: "Read aloud", colorHex: "#C3A3D4",
              triggers: [Trigger(combo: KeyCombo(key: .r, modifiers: [.option]), mode: .toggle)],
              steps: [Step(kind: .text(sources: [.selection, .page, .clipboard])),
                      Step(kind: .localSpeech(engine: .pocket, voice: LocalVoiceEngine.pocket.defaultVoice, rate: 1.0))]),
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
