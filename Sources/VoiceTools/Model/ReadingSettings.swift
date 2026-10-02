import AppKit
import Foundation

/// How a reading (anything read aloud) is steered from the keyboard: when the HUD takes the keys, what clicking
/// away does, which keys do what while it has them, and optional shortcuts that work anywhere while reading.
/// Kept in config.toml under [settings.reading].
struct ReadingSettings: Equatable {
    /// When the HUD takes the keyboard. It never brings Voice Pipes to the front: the app you're in stays active,
    /// and typing goes back to it when the HUD lets go.
    enum TakeKeys: String, CaseIterable {
        /// As soon as something starts being read.
        case always
        /// When the pointer moves onto the HUD, or you click it (the default).
        case hover
        /// Only when you click it.
        case click
        case never

        var label: String {
            switch self {
            case .always: "Always"
            case .hover: "Point or click"
            case .click: "Click"
            case .never: "Never"
            }
        }
    }

    enum ClickAway: String, CaseIterable {
        case keepReading = "keep-reading"
        case stop
    }

    enum Action: String, CaseIterable, Identifiable {
        case stop, pause, next, previous, slower, faster, start, end
        var id: String { rawValue }

        var label: String {
            switch self {
            case .stop: "Stop and close"
            case .pause: "Pause / resume"
            case .next: "Next sentence"
            case .previous: "Previous sentence"
            case .slower: "Slower"
            case .faster: "Faster"
            case .start: "Back to the start"
            case .end: "Last sentence"
            }
        }
    }

    var takeKeys: TakeKeys = .hover
    var clickAway: ClickAway = .keepReading
    /// Keys while the HUD has the keyboard (plain keys are fine: they only work then).
    var keys: [Action: [KeyCombo]] = ReadingSettings.defaultKeys
    /// Shortcuts that work in any app, but only while something is being read. None by default.
    var global: [Action: KeyCombo] = [:]

    /// Vim-style defaults, with arrows and −/+ for everyone else.
    static let defaultKeyNames: [Action: [String]] = [
        .stop: ["escape"], .pause: ["space"], .next: ["j", "down"], .previous: ["k", "up"],
        .slower: ["h", "minus"], .faster: ["l", "equal"], .start: ["g"], .end: ["shift+g"],
    ]

    static let defaultKeys: [Action: [KeyCombo]] = defaultKeyNames.mapValues { $0.compactMap { try? KeyNames.parse($0) } }

    /// The action a key press means while the HUD has the keyboard. Modifiers must match exactly (so G and
    /// shift+G differ); the arrow keys' extra function/keypad flags are ignored.
    func action(for event: NSEvent) -> Action? {
        let pressed = KeyCombo(key: .init(code: UInt32(event.keyCode)), modifiers: .init(event.modifierFlags))
        return Action.allCases.first { (keys[$0] ?? []).contains(pressed) }
    }
}

/// What agents using Voice Pipes read aloud to you without being asked ([settings.agents] in config.toml). Agents
/// don't remember between sessions, so this is where the preference lives: the skill and `vp agents context` read it.
struct AgentSettings: Equatable {
    enum ReadAloud: String, CaseIterable {
        /// Only when you ask.
        case off
        /// Long, rich text: summaries, reports, explanations; not short replies.
        case long
        /// Long text, plus anything that needs you: a question, a decision, a finished task, a problem.
        case attention
        /// Every reply.
        case all

        var meaning: String {
            switch self {
            case .off: "only when you ask"
            case .long: "long, rich text (summaries, reports, explanations), not short replies"
            case .attention: "long text, plus anything that needs you: a question, a decision, a finished task, a problem"
            case .all: "every reply"
            }
        }
    }

    var readAloud: ReadAloud = .off
    /// Text longer than this (characters) counts as long.
    var longText = 600
}
