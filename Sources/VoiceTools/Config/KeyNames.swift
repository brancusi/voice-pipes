import Carbon.HIToolbox
import Foundation

/// Hotkeys as text, for the config file and the CLI: `"option+space"`, `"control+shift+r"`, `"command+f5"`.
/// Modifiers first (control, option, shift, command; aliases ctrl, alt/opt, cmd), then one key, joined with `+`.
/// Letters and digits follow the current keyboard layout, the way the app shows them.
enum KeyNames {
    static let modifierNames: [(String, KeyCombo.Modifiers)] = [
        ("control", .control), ("option", .option), ("shift", .shift), ("command", .command),
    ]
    private static let modifierAliases: [String: KeyCombo.Modifiers] = [
        "control": .control, "ctrl": .control, "⌃": .control,
        "option": .option, "opt": .option, "alt": .option, "⌥": .option,
        "shift": .shift, "⇧": .shift,
        "command": .command, "cmd": .command, "⌘": .command,
    ]

    /// Named keys, by their config spelling.
    static let named: [(String, Int)] = [
        ("space", kVK_Space), ("return", kVK_Return), ("tab", kVK_Tab), ("escape", kVK_Escape), ("delete", kVK_Delete),
        ("forward-delete", kVK_ForwardDelete), ("left", kVK_LeftArrow), ("right", kVK_RightArrow), ("up", kVK_UpArrow),
        ("down", kVK_DownArrow), ("home", kVK_Home), ("end", kVK_End), ("page-up", kVK_PageUp), ("page-down", kVK_PageDown),
        ("f1", kVK_F1), ("f2", kVK_F2), ("f3", kVK_F3), ("f4", kVK_F4), ("f5", kVK_F5), ("f6", kVK_F6), ("f7", kVK_F7),
        ("f8", kVK_F8), ("f9", kVK_F9), ("f10", kVK_F10), ("f11", kVK_F11), ("f12", kVK_F12), ("f13", kVK_F13),
        ("f14", kVK_F14), ("f15", kVK_F15), ("f16", kVK_F16), ("f17", kVK_F17), ("f18", kVK_F18), ("f19", kVK_F19),
        ("f20", kVK_F20), ("minus", kVK_ANSI_Minus), ("equal", kVK_ANSI_Equal), ("comma", kVK_ANSI_Comma),
        ("period", kVK_ANSI_Period), ("slash", kVK_ANSI_Slash), ("semicolon", kVK_ANSI_Semicolon), ("quote", kVK_ANSI_Quote),
        ("backslash", kVK_ANSI_Backslash), ("grave", kVK_ANSI_Grave), ("left-bracket", kVK_ANSI_LeftBracket),
        ("right-bracket", kVK_ANSI_RightBracket),
    ]
    private static let namedByCode = Dictionary(named.map { ($0.1, $0.0) }, uniquingKeysWith: { a, _ in a })
    private static let codeByName = Dictionary(named.map { ($0.0, $0.1) }, uniquingKeysWith: { a, _ in a })
    private static let aliases: [String: String] = ["esc": "escape", "enter": "return", "backspace": "delete", "spacebar": "space"]

    /// US-layout positions, used when the current layout has no key that types the character.
    private static let ansi: [Character: Int] = [
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E, "f": kVK_ANSI_F,
        "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
        "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R,
        "s": kVK_ANSI_S, "t": kVK_ANSI_T, "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
        "y": kVK_ANSI_Y, "z": kVK_ANSI_Z, "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
        "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
    ]

    enum ParseError: Error, CustomStringConvertible {
        case empty, unknownModifier(String), unknownKey(String), noKey, twoKeys
        var description: String {
            switch self {
            case .empty: "is empty"
            case .unknownModifier(let m): "has an unknown modifier '\(m)' (use control, option, shift, command)"
            case .unknownKey(let k): "has an unknown key '\(k)' (a letter, a digit, space, return, tab, escape, f1–f20, an arrow, …)"
            case .noKey: "names modifiers but no key"
            case .twoKeys: "names more than one key"
            }
        }
    }

    static func parse(_ text: String) throws -> KeyCombo {
        let parts = text.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard let last = parts.last else { throw ParseError.empty }
        var modifiers: KeyCombo.Modifiers = []
        for part in parts.dropLast() {
            guard let modifier = modifierAliases[part] else {
                throw modifierAliases[last] == nil && (codeByName[part] != nil || part.count == 1)
                    ? ParseError.twoKeys : ParseError.unknownModifier(part)
            }
            modifiers.insert(modifier)
        }
        return KeyCombo(key: .init(code: try code(for: last)), modifiers: modifiers)
    }

    private static func code(for name: String) throws -> UInt32 {
        let name = aliases[name] ?? name
        if let code = codeByName[name] { return UInt32(code) }
        if name.count == 1, let character = name.first {
            if let code = KeyCombo.keyCode(producing: character) { return code }
            if let code = ansi[character] { return UInt32(code) }
        }
        if modifierAliases[name] != nil { throw ParseError.noKey }
        throw ParseError.unknownKey(name)
    }

    /// `option+space`, `control+shift+r`.
    static func format(_ combo: KeyCombo) -> String {
        var parts = modifierNames.filter { combo.modifiers.contains($0.1) }.map(\.0)
        let code = Int(combo.key.code)
        if let name = namedByCode[code] {
            parts.append(name)
        } else {
            let display = KeyCombo.name(for: combo.key.code).lowercased()
            parts.append(display.count == 1 ? display : "key-\(code)")
        }
        return parts.joined(separator: "+")
    }
}
