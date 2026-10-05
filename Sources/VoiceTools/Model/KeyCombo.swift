import AppKit
import Carbon.HIToolbox

/// A key plus modifiers, stored as a Carbon virtual key code so it can be registered as a global hotkey.
struct KeyCombo: Codable, Hashable {
    struct Key: Codable, Hashable {
        var code: UInt32

        static let space = Key(code: UInt32(kVK_Space))
        static let r = Key(code: UInt32(kVK_ANSI_R))
        static let n = Key(code: UInt32(kVK_ANSI_N))
        static let escape = Key(code: UInt32(kVK_Escape))
    }

    struct Modifiers: OptionSet, Codable, Hashable {
        let rawValue: UInt32
        static let command = Modifiers(rawValue: 1 << 0)
        static let option = Modifiers(rawValue: 1 << 1)
        static let control = Modifiers(rawValue: 1 << 2)
        static let shift = Modifiers(rawValue: 1 << 3)

        init(rawValue: UInt32) { self.rawValue = rawValue }

        init(_ flags: NSEvent.ModifierFlags) {
            var m: Modifiers = []
            if flags.contains(.command) { m.insert(.command) }
            if flags.contains(.option) { m.insert(.option) }
            if flags.contains(.control) { m.insert(.control) }
            if flags.contains(.shift) { m.insert(.shift) }
            self = m
        }

        var carbonFlags: UInt32 {
            var f: UInt32 = 0
            if contains(.command) { f |= UInt32(cmdKey) }
            if contains(.option) { f |= UInt32(optionKey) }
            if contains(.control) { f |= UInt32(controlKey) }
            if contains(.shift) { f |= UInt32(shiftKey) }
            return f
        }
    }

    var key: Key
    var modifiers: Modifiers

    var display: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        // "⇧⌘C": a character sits right against its modifiers; a named key keeps a space ("⌥ Space", "⌘ Return").
        let name = Self.name(for: key.code)
        return s.isEmpty ? name : s + (name.count == 1 ? "" : " ") + name
    }

    static func name(for code: UInt32) -> String {
        if let named = specialNames[Int(code)] { return named }
        return characterName(for: code) ?? "Key \(code)"
    }

    private static let specialNames: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Escape: "Esc", kVK_Delete: "⌫",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17",
        kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
    ]

    /// The key code that types `character` in the current keyboard layout.
    static func keyCode(producing character: Character) -> UInt32? {
        let target = String(character).uppercased()
        return (0..<128).first { characterName(for: UInt32($0)) == target }.map(UInt32.init)
    }

    /// Uses the current keyboard layout so letters show as the user sees them.
    private static func characterName(for code: UInt32) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        return data.withUnsafeBytes { raw -> String? in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            var deadKeys: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var length = 0
            let status = UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0,
                                        UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                        &deadKeys, chars.count, &length, &chars)
            guard status == noErr, length > 0 else { return nil }
            return String(utf16CodeUnits: chars, count: length).uppercased()
        }
    }
}
