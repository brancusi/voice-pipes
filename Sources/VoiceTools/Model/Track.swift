import Foundation

/// A track is a named pipeline: one or more triggers start it, and its steps run in order,
/// each step consuming the previous step's output.
struct Track: Codable, Identifiable, Hashable {
    var id = UUID()
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
    case http(url: String, method: String, headers: [String: String], bodyTemplate: String, responseField: String)
    case template(String)

    // Outputs
    case paste(restoreClipboard: Bool)
    case copy
    case speak(voiceID: String?, rate: Float)
    case openRouterSpeech(model: String, voice: String, rate: Float)
    case showHUD

    var input: DataKind {
        switch self {
        case .microphone, .text: .none
        case .parakeet, .openRouterSTT: .audio
        case .llm, .http, .template, .paste, .copy, .speak, .openRouterSpeech, .showHUD: .text
        }
    }

    var output: DataKind {
        switch self {
        case .microphone: .audio
        case .text, .parakeet, .openRouterSTT, .llm, .http, .template: .text
        // Outputs pass their text through so a track can, e.g., paste and then POST.
        case .paste, .copy, .showHUD: .text
        case .speak, .openRouterSpeech: .none
        }
    }

    var category: String {
        switch self {
        case .microphone, .text: "Input"
        case .parakeet, .openRouterSTT: "Transcribe"
        case .llm, .http, .template: "Transform"
        case .paste, .copy, .speak, .openRouterSpeech, .showHUD: "Output"
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
        case .http(let url, let method, _, _, _): "\(method) \(URL(string: url)?.host ?? url)"
        case .template: "Text template"
        case .paste: "Paste at cursor"
        case .copy: "Copy to clipboard"
        case .speak: "Speak · macOS voice"
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
        case .http(_, let method, _, _, _): method
        case .template: "Template"
        case .paste: "Paste"
        case .copy: "Copy"
        case .speak: "Speak"
        case .openRouterSpeech(_, let voice, _): "Speak · \(OpenRouterCatalog.Model.voiceLabel(voice).components(separatedBy: " (").first ?? voice)"
        case .showHUD: "HUD"
        }
    }

    static let defaultSpeechModel = "microsoft/mai-voice-2.1"
    static let defaultSpeechVoice = "en-US-Harper:MAI-Voice-2.1"

    /// Catalog for the "Add step" menu.
    static let catalog: [StepKind] = [
        .microphone,
        .text(sources: [.selection, .page, .clipboard]),
        .parakeet(chunkOnPauseMs: 500, mode: .onRelease),
        .openRouterSTT(model: "microsoft/mai-transcribe-2"),
        .llm(model: "anthropic/claude-haiku-4.5", prompt: "", onFailure: .passThrough),
        .http(url: "https://", method: "POST", headers: ["Content-Type": "application/json"],
              bodyTemplate: #"{"text": {{input_json}}}"#, responseField: ""),
        .template("{{input}}"),
        .paste(restoreClipboard: true),
        .copy,
        .openRouterSpeech(model: StepKind.defaultSpeechModel, voice: StepKind.defaultSpeechVoice, rate: 1.0),
        .speak(voiceID: nil, rate: 1.0),
        .showHUD,
    ]
}

extension Track {
    /// Returns a description of the first type mismatch between adjacent steps, if any.
    var validationError: String? {
        guard let first = steps.first else { return "Add at least one step." }
        if first.kind.input != .none { return "The first step must be an input." }
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
        Track(name: "Fast dictation", colorHex: "#D9731A",
              triggers: [Trigger(combo: KeyCombo(key: .space, modifiers: [.option]), mode: .hold)],
              steps: [Step(kind: .microphone), Step(kind: .parakeet(chunkOnPauseMs: 500, mode: .onRelease)),
                      Step(kind: .paste(restoreClipboard: true))]),
        Track(name: "Clean dictation", colorHex: "#0A66D8",
              triggers: [Trigger(combo: KeyCombo(key: .space, modifiers: [.option, .shift]), mode: .toggle)],
              steps: [Step(kind: .microphone), Step(kind: .openRouterSTT(model: "microsoft/mai-transcribe-2")),
                      Step(kind: .llm(model: "anthropic/claude-haiku-4.5", prompt: cleanupPrompt, onFailure: .passThrough)),
                      Step(kind: .paste(restoreClipboard: true))]),
        Track(name: "Read aloud", colorHex: "#6B4FD1",
              triggers: [Trigger(combo: KeyCombo(key: .r, modifiers: [.option]), mode: .toggle)],
              steps: [Step(kind: .text(sources: [.selection, .page, .clipboard])),
                      Step(kind: .openRouterSpeech(model: StepKind.defaultSpeechModel,
                                                   voice: StepKind.defaultSpeechVoice, rate: 1.0))]),
    ]
}
