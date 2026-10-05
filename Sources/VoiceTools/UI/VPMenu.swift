import AppKit
import SwiftUI

/// A right-click menu in Voice Pipes' own look (the system's context menu can't be styled): a card in the Sundown
/// palette with an optional header, rows with their keyboard shortcut in muted text, and destructive rows in red.
/// It opens at the pointer; ↑↓ and Return work, and Esc, a click elsewhere or leaving the app closes it.
enum VPMenuEntry {
    case item(VPMenuItem)
    case divider
}

struct VPMenuItem {
    var title: String
    var shortcut: String?
    var destructive = false
    var enabled = true
    var action: () -> Void
}

/// The header line: what the menu is about (a track's colour and name).
struct VPMenuHeader {
    var title: String
    var color: Color?
    var detail: String?
}

@MainActor
final class VPMenuPanel {
    static let shared = VPMenuPanel()

    private var panel: NSPanel?
    private var monitor: Any?
    private var resignObserver: NSObjectProtocol?

    /// Shows the menu with its top-left corner at `point` (screen coordinates), kept on screen.
    func show(_ entries: [VPMenuEntry], header: VPMenuHeader? = nil, at point: NSPoint) {
        close()
        let host = NSHostingView(rootView: VPMenuView(entries: entries, header: header) { [weak self] action in
            self?.close()
            action?()
        })
        let size = host.fittingSize
        let screen = NSScreen.screens.first { $0.frame.contains(point) }?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        var origin = NSPoint(x: point.x, y: point.y - size.height)
        origin.x = min(max(origin.x, screen.minX + 4), screen.maxX - size.width - 4)
        if origin.y < screen.minY + 4 { origin.y = point.y }  // no room below: open upwards

        let panel = KeyPanel(contentRect: NSRect(origin: origin, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.contentView = host
        panel.appearance = NSApp.effectiveAppearance
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel

        // A click anywhere else closes it (and still does what it was for).
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            if event.window !== self?.panel { self?.close() }
            return event
        }
        resignObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    func close() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        panel?.orderOut(nil)
        panel = nil
    }

    #if SNAPSHOTS
    /// Harness only: the menu as drawn, with a row highlighted.
    static func preview(_ entries: [VPMenuEntry], header: VPMenuHeader?, highlighted: Int?) -> some View {
        VPMenuView(entries: entries, header: header, finish: { _ in }, initialHighlight: highlighted)
    }
    #endif

    /// Borderless panels can't take the keyboard by default; this one needs ↑↓, Return and Esc.
    private final class KeyPanel: NSPanel {
        override var canBecomeKey: Bool { true }
    }
}

private struct VPMenuView: View {
    let entries: [VPMenuEntry]
    let header: VPMenuHeader?
    /// Closes the menu, then runs the chosen item's action (nil: just close).
    let finish: ((() -> Void)?) -> Void
    var initialHighlight: Int?

    @State private var highlighted: Int?
    @FocusState private var focused: Bool

    private var items: [(index: Int, item: VPMenuItem)] {
        entries.enumerated().compactMap { i, e in if case .item(let item) = e { (i, item) } else { nil } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let header {
                HStack(spacing: 8) {
                    if let color = header.color { Rectangle().fill(color).frame(width: 7, height: 7) }
                    Text(header.title).font(VPFont.bodyStrong).foregroundStyle(Palette.fg).lineLimit(1)
                    Spacer(minLength: 12)
                    if let detail = header.detail { Text(detail).font(VPFont.caption).foregroundStyle(Palette.fgMuted) }
                }
                .padding(.horizontal, 10).padding(.top, 6).padding(.bottom, 8)
                Rectangle().fill(Palette.line).frame(height: 1).padding(.bottom, 4)
            }
            ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                switch entry {
                case .divider:
                    Rectangle().fill(Palette.line).frame(height: 1).padding(.vertical, 4)
                case .item(let item):
                    row(item, index: index)
                }
            }
        }
        .padding(4)
        .frame(minWidth: 220, alignment: .leading)
        .fixedSize()
        .background(RoundedRectangle(cornerRadius: 6).fill(Palette.bg200))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .vpWindow()
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear { focused = true; highlighted = initialHighlight }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.return) {
            if let highlighted, case .item(let item) = entries[highlighted], item.enabled { finish(item.action) }
            return .handled
        }
        .onKeyPress(.escape) { finish(nil); return .handled }
    }

    private func row(_ item: VPMenuItem, index: Int) -> some View {
        let on = highlighted == index && item.enabled
        return Button { if item.enabled { finish(item.action) } } label: {
            HStack(spacing: 16) {
                Text(item.title)
                    .font(VPFont.body)
                    .foregroundStyle(!item.enabled ? Palette.comment : item.destructive ? Palette.red : Palette.fg)
                Spacer(minLength: 12)
                if let shortcut = item.shortcut { Text(shortcut).font(VPFont.caption).tracking(0.7).foregroundStyle(Palette.fgMuted) }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 4).fill(on ? (item.destructive ? Palette.red.opacity(0.14) : Palette.bg300) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!item.enabled)
        .onHover { inside in
            if inside { highlighted = index } else if highlighted == index { highlighted = nil }
        }
    }

    private func move(_ delta: Int) {
        let enabled = items.filter { $0.item.enabled }.map { $0.index }
        guard !enabled.isEmpty else { return }
        guard let current = highlighted, let at = enabled.firstIndex(of: current) else {
            highlighted = delta > 0 ? enabled.first : enabled.last
            return
        }
        highlighted = enabled[(at + delta + enabled.count) % enabled.count]
    }
}

/// Catches a right-click (or a Control-click) on the view it's laid over, and lets every other click through.
struct RightClickArea: NSViewRepresentable {
    let onRightClick: (NSPoint) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onRightClick = onRightClick
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) { view.onRightClick = onRightClick }

    final class CatcherView: NSView {
        var onRightClick: ((NSPoint) -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent else { return nil }
            let secondary = event.type == .rightMouseDown || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
            return secondary ? super.hitTest(point) : nil
        }

        override func rightMouseDown(with event: NSEvent) { onRightClick?(NSEvent.mouseLocation) }

        override func mouseDown(with event: NSEvent) {
            if event.modifierFlags.contains(.control) { onRightClick?(NSEvent.mouseLocation) } else { super.mouseDown(with: event) }
        }
    }
}
