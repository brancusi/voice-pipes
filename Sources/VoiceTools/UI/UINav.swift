import AppKit
import SwiftUI

/// What `vp open` / `vp close` ask the windows to show, and what they report back for `vp ui`.
///
/// Requests are one-shot: the page that owns that state takes it (on appear, or when it changes) and clears it, so
/// a request made before its window exists still lands. Keys name elements across the app: `step-<uuid>`,
/// `route-<uuid>`, `run-<uuid>`, `vocab-<uuid>`, `setup-<section>`; field keys are the config file's names
/// (`name`, `prompt`, `url`, `route2.when`, …).
@MainActor @Observable
final class UINav {
    static let shared = UINav()

    // MARK: Requests

    struct EditorRequest: Equatable {
        var track: Track.ID
        var step: Int?
        var route: Int?
        var section: String?
        /// Open the step's settings (false: just scroll to it).
        var expand = true
    }

    struct HistoryRequest: Equatable {
        var track: String?
        var search: String?
        var run: RunRecord.ID?
    }

    struct VocabularyRequest: Equatable {
        var word: String?
        var add = false
    }

    struct Flash: Equatable {
        var keys: Set<String>
        var at = Date()
    }

    struct FocusRequest: Equatable {
        var key: String
        var at = Date()
    }

    var editor: EditorRequest?
    var history: HistoryRequest?
    var vocabulary: VocabularyRequest?
    var setupSection: String?
    var onboardingStep: Int?
    struct RouteRequest: Equatable {
        var step: Step.ID
        var index: Int
    }

    /// A route card to open for editing: the route step and the route's position.
    var openRoute: RouteRequest?
    var focus: FocusRequest?
    var flash: Flash?
    /// Bumped by `vp close sheet`: open sheets close.
    var dismissSheets = 0

    // MARK: Reported by the pages (for `vp ui`)

    var expandedStep: Int?
    var editingRoutes: [Int] = []
    var focusedField: String?
    var historyTrack: String?
    var historySearch = ""
    var currentOnboardingStep: Int?
    var sheet: String?

    func highlight(_ keys: String...) { highlight(Set(keys)) }
    func highlight(_ keys: Set<String>) { if !keys.isEmpty { flash = Flash(keys: keys) } }

    /// Focus a field once it's on screen (a step's fields appear only after it expands).
    func focusField(_ key: String) { focus = FocusRequest(key: key) }

    /// Called by a field when it appears or a request changes: true when it should take focus now.
    func takeFocus(_ key: String?) -> Bool {
        guard let key, let focus, focus.key == key, Date().timeIntervalSince(focus.at) < 5 else { return false }
        self.focus = nil
        return true
    }

    /// While set, opening a window doesn't bring the app to the front (`vp open --background`).
    var quietOpen = false
}

// MARK: Flash

extension View {
    /// Outlines this element in rose for a moment when `vp open` (or an outside edit to config.toml) points at it.
    /// `outset` draws it outside the element (for a section whose label sits at its top edge).
    func vpFlash(_ key: String, cornerRadius: CGFloat = 4, outset: CGFloat = 0) -> some View {
        modifier(FlashModifier(key: key, cornerRadius: cornerRadius, outset: outset))
    }
}

private struct FlashModifier: ViewModifier {
    let key: String
    let cornerRadius: CGFloat
    var outset: CGFloat = 0
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius + outset)
                    .strokeBorder(Palette.pink, lineWidth: 2)
                    .padding(-outset)
                    .opacity(shown ? 1 : 0)
                    .allowsHitTesting(false)
            )
            .onChange(of: UINav.shared.flash) { _, flash in play(flash) }
            .onAppear { play(UINav.shared.flash) }
    }

    private func play(_ flash: UINav.Flash?) {
        // On appear, only a fresh flash (the element was just scrolled to or created).
        guard let flash, flash.keys.contains(key), Date().timeIntervalSince(flash.at) < 1.5 else { return }
        shown = true
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 1.2).delay(1.0)) { shown = false }
        }
    }
}

// MARK: Focus

/// Gives a field a name `vp open … --field <name>` can focus, and reports it as focused for `vp ui`.
struct FocusKeyModifier: ViewModifier {
    let key: String?
    var focused: FocusState<Bool>.Binding

    func body(content: Content) -> some View {
        content
            .onAppear { take() }
            .onDisappear { if let key, UINav.shared.focusedField == key { UINav.shared.focusedField = nil } }
            .onChange(of: UINav.shared.focus) { _, _ in take() }
            .onChange(of: focused.wrappedValue) { _, isFocused in
                guard let key else { return }
                if isFocused { UINav.shared.focusedField = key } else if UINav.shared.focusedField == key { UINav.shared.focusedField = nil }
            }
    }

    private func take() {
        guard UINav.shared.takeFocus(key) else { return }
        // After the field is in a window (it may have just appeared with its step).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { focused.wrappedValue = true }
    }
}

// MARK: The menu bar panel

/// The MenuBarExtra panel, opened and closed the way a click on the icon would (SwiftUI has no API for it).
@MainActor
enum MenuBarPanel {
    static var isOpen: Bool { panel?.isVisible ?? false }

    static func open() { if !isOpen { statusButton?.performClick(nil) } }
    static func close() { if isOpen { statusButton?.performClick(nil) } }

    private static var panel: NSWindow? {
        NSApp.windows.first { NSStringFromClass(type(of: $0)).contains("MenuBarExtra") }
    }

    private static var statusButton: NSStatusBarButton? {
        for window in NSApp.windows where NSStringFromClass(type(of: window)).contains("StatusBar") {
            if let button = find(in: window.contentView) { return button }
        }
        return nil
    }

    private static func find(in view: NSView?) -> NSStatusBarButton? {
        guard let view else { return nil }
        if let button = view as? NSStatusBarButton { return button }
        for sub in view.subviews { if let found = find(in: sub) { return found } }
        return nil
    }
}
