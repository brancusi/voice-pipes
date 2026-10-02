import AppKit
import ApplicationServices

/// Clipboard access plus a tiny history so tracks can read the *previous* clipboard entry.
@MainActor
final class Clipboard {
    static let shared = Clipboard()

    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var history: [String] = []
    private var timer: Timer?
    /// While we write to the pasteboard ourselves, don't record it as user history.
    private var suppressUntilChange: Int?

    private init() {
        lastChangeCount = pasteboard.changeCount
        if let current = pasteboard.string(forType: .string) { history = [current] }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            MainActor.assumeIsolated { Clipboard.shared.poll() }
        }
    }

    var current: String? { pasteboard.string(forType: .string) }
    var previous: String? { history.count > 1 ? history[history.count - 2] : nil }

    private func poll() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        if let suppress = suppressUntilChange, pasteboard.changeCount <= suppress { return }
        suppressUntilChange = nil
        guard let text = pasteboard.string(forType: .string), text != history.last else { return }
        history.append(text)
        if history.count > 10 { history.removeFirst() }
    }

    func copy(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Pastes into the focused app with ⌘V, optionally restoring what was on the clipboard.
    /// Without Accessibility permission macOS drops the keystroke silently, so in that case the text is left on
    /// the clipboard and this throws, rather than pretending it pasted.
    func paste(_ text: String, restore: Bool) async throws {
        guard AXIsProcessTrusted() else {
            copy(text)
            throw PasteError.notTrusted
        }
        let saved = restore ? snapshot() : nil
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        suppressUntilChange = pasteboard.changeCount + (restore ? 1 : 0)
        await Keystroke.waitForModifiersReleased()
        Keystroke.send("v", flags: .maskCommand)
        guard let saved else { return }
        // Give the target app time to read the pasteboard, then restore in the background so the
        // track finishes (and reports its time) without waiting for it.
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            restoreSnapshot(saved)
        }
    }

    /// Copies the current selection in the focused app via ⌘C, then restores the clipboard.
    func copySelection() async -> String? {
        let saved = snapshot()
        let before = pasteboard.changeCount
        suppressUntilChange = before + 2
        await Keystroke.waitForModifiersReleased()
        Keystroke.send("c", flags: .maskCommand)
        for _ in 0..<20 where pasteboard.changeCount == before {
            try? await Task.sleep(for: .milliseconds(15))
        }
        let text = pasteboard.changeCount != before ? pasteboard.string(forType: .string) : nil
        restoreSnapshot(saved)
        return text
    }

    private func snapshot() -> [[NSPasteboard.PasteboardType: Data]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in item.data(forType: type).map { (type, $0) } })
        }
    }

    private func restoreSnapshot(_ items: [[NSPasteboard.PasteboardType: Data]]) {
        pasteboard.clearContents()
        let restored = items.map { entry -> NSPasteboardItem in
            let item = NSPasteboardItem()
            entry.forEach { item.setData($1, forType: $0) }
            return item
        }
        if !restored.isEmpty { pasteboard.writeObjects(restored) }
    }
}

enum PasteError: LocalizedError {
    case notTrusted

    var errorDescription: String? {
        "Couldn't paste: Voice Pipes needs Accessibility permission (macOS may reset it after an update). The text is on the clipboard; press ⌘V."
    }
}

enum Keystroke {
    private static let modifierMask: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]

    /// Waits until the trigger's modifier keys are let go: held keys would otherwise merge into the
    /// synthetic shortcut (⌥ held from ⌥ Space turns ⌘V into ⌥⌘V, which most apps ignore).
    static func waitForModifiersReleased(timeout: Duration = .milliseconds(1500)) async {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline,
              !CGEventSource.flagsState(.hidSystemState).intersection(modifierMask).isEmpty {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    /// Sends a shortcut by character, so it works on any keyboard layout (V isn't key code 9 on Dvorak).
    static func send(_ character: Character, flags: CGEventFlags) {
        let fallback: CGKeyCode = character == "c" ? 8 : 9
        let code = KeyCombo.keyCode(producing: character).map { CGKeyCode($0) } ?? fallback
        // A private event source carries only the flags set here, never the keys physically held.
        let source = CGEventSource(stateID: .privateState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cgSessionEventTap)
        up?.post(tap: .cgSessionEventTap)
    }
}
