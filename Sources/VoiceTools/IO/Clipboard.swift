import AppKit

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
    func paste(_ text: String, restore: Bool) async {
        let saved = restore ? snapshot() : nil
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        suppressUntilChange = pasteboard.changeCount + (restore ? 1 : 0)
        Keystroke.send(keyCode: 9, flags: .maskCommand) // V
        guard let saved else { return }
        // Give the target app time to read the pasteboard before restoring.
        try? await Task.sleep(for: .milliseconds(250))
        restoreSnapshot(saved)
    }

    /// Copies the current selection in the focused app via ⌘C, then restores the clipboard.
    func copySelection() async -> String? {
        let saved = snapshot()
        let before = pasteboard.changeCount
        suppressUntilChange = before + 2
        Keystroke.send(keyCode: 8, flags: .maskCommand) // C
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

enum Keystroke {
    static func send(keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
