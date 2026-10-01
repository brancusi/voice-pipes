import AppKit
import ApplicationServices

/// Reads text from the frontmost app through the Accessibility API.
@MainActor
enum TextCapture {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func promptForAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func read(_ source: TextSource) async -> String? {
        let text: String? = switch source {
        case .selection: await selection()
        case .page: page()
        case .clipboard: Clipboard.shared.current
        case .previousClipboard: Clipboard.shared.previous
        }
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    /// Selected text via AX, falling back to a ⌘C round trip for apps that don't expose it (e.g. Chrome, Electron).
    static func selection() async -> String? {
        if let element = focusedElement(),
           let selected = attribute(element, kAXSelectedTextAttribute) as? String, !selected.isEmpty {
            return selected
        }
        return await Clipboard.shared.copySelection()
    }

    /// Visible text of the focused window, preferring a web area if there is one.
    static func page() -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let window = attribute(appElement, kAXFocusedWindowAttribute) else { return nil }
        let root = findWebArea(window as! AXUIElement, depth: 0) ?? (window as! AXUIElement)
        var parts: [String] = []
        collectText(root, into: &parts, depth: 0)
        let text = parts.joined(separator: " ")
        return text.isEmpty ? nil : text
    }

    private static func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        guard let value = attribute(system, kAXFocusedUIElementAttribute) else { return nil }
        return (value as! AXUIElement)
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        (attribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    }

    private static func findWebArea(_ element: AXUIElement, depth: Int) -> AXUIElement? {
        if (attribute(element, kAXRoleAttribute) as? String) == "AXWebArea" { return element }
        guard depth < 12 else { return nil }
        for child in children(element) {
            if let found = findWebArea(child, depth: depth + 1) { return found }
        }
        return nil
    }

    private static func collectText(_ element: AXUIElement, into parts: inout [String], depth: Int) {
        guard depth < 40, parts.count < 5_000 else { return }
        let role = attribute(element, kAXRoleAttribute) as? String
        if role == kAXStaticTextRole, let value = attribute(element, kAXValueAttribute) as? String, !value.isEmpty {
            parts.append(value)
        }
        for child in children(element) { collectText(child, into: &parts, depth: depth + 1) }
    }
}
