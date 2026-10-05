import AppKit
import SwiftUI

/// Where a new step goes: the track's pipeline or a named branch, after which step, and which keys exist.
struct StepPickerContext {
    var branch: String?
    var previous: StepKind?
    var hasOpenRouterKey: Bool
    var hasJevKey: Bool

    /// What the new step will receive: the previous step's output; a branch starts from text; a track from nothing.
    var input: DataKind { previous?.output ?? (branch != nil ? .text : .none) }
    var isStart: Bool { previous == nil && branch == nil }
}

extension StepKind {
    /// The block's name in the picker (the model is chosen inside, so no provider).
    var pickerName: String {
        switch self {
        case .microphone: "Microphone"
        case .text: "Text"
        case .parakeet, .openRouterSTT: "Transcribe"
        case .llm: "LLM"
        case .route: "Route · Jev"
        case .branch: "Branch · Jev"
        case .http: "HTTP request"
        case .template: "Text template"
        case .fixWords: "Fix words"
        case .paste: "Paste at cursor"
        case .copy: "Copy to clipboard"
        case .speak, .openRouterSpeech, .localSpeech: "Speak"
        case .showHUD: "Show in HUD"
        }
    }

    var pickerDetail: String {
        switch self {
        case .microphone: "Record while the hotkey is held or toggled"
        case .text: "Selected text, then the page, then the clipboard"
        case .parakeet, .openRouterSTT: "Parakeet on this Mac or any OpenRouter model"
        case .llm: "Rewrite, answer or translate with your instructions"
        case .route: "Jev picks the model and prompt for each request"
        case .branch: "Jev picks a branch; each runs its own steps"
        case .http: "Send the text anywhere and use the reply"
        case .template: "Wrap the text: {{input}}"
        case .fixWords: "Your vocabulary, applied instantly on this Mac"
        case .paste: "Types it into the app you're in"
        case .copy: "Leaves it on the clipboard"
        case .speak, .openRouterSpeech, .localSpeech: "Read it aloud, on this Mac or in the cloud"
        case .showHUD: "Flashes it at the bottom of the screen"
        }
    }
}

/// The popover behind "+ Add step": blocks by category, what fits here first, filterable from the keyboard.
struct StepPicker: View {
    let context: StepPickerContext
    let onAdd: (StepKind) -> Void
    let onClose: () -> Void
    var onHeight: (CGFloat) -> Void = { _ in }
    /// Harness only: a filter already typed.
    var initialQuery = ""

    @State private var query = ""
    @State private var highlighted: Int?
    @FocusState private var filterFocused: Bool

    static let width: CGFloat = 440
    static let maxHeight: CGFloat = 520
    private static let rowHeight: CGFloat = 40
    private static let headerHeight: CGFloat = 28
    private static let categories = ["Input", "Transcribe", "Transform", "Output"]

    struct Entry: Identifiable {
        let id: Int
        let kind: StepKind
        let fits: Bool
        let reason: String?
        let keyTag: String?
    }

    /// Every block that can go here: fitting ones by category, then the rest.
    private var entries: [Entry] {
        let available = StepKind.catalog.filter { context.branch == nil || $0.category != "Input" }
        let all = available.enumerated().map { i, kind -> Entry in
            let fits: Bool
            let reason: String?
            if kind.input == .none {
                fits = context.isStart
                reason = fits ? nil : "starts a pipeline"
            } else {
                fits = !context.isStart && kind.input == context.input
                reason = fits ? nil : "needs \(kind.input.rawValue)"
            }
            let tag: String? = switch kind {
            case .route, .branch: context.hasJevKey ? nil : "NEEDS JEV KEY"
            case .llm: context.hasOpenRouterKey ? nil : "NEEDS OPENROUTER KEY"
            default: nil
            }
            return Entry(id: i, kind: kind, fits: fits, reason: reason, keyTag: tag)
        }
        let order = { (e: Entry) in Self.categories.firstIndex(of: e.kind.category) ?? 0 }
        return all.filter(\.fits).sorted { (order($0), $0.id) < (order($1), $1.id) }
            + all.filter { !$0.fits }.sorted { (order($0), $0.id) < (order($1), $1.id) }
    }

    private var visible: [Entry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return entries }
        return entries.filter {
            $0.kind.pickerName.localizedCaseInsensitiveContains(q) || $0.kind.pickerDetail.localizedCaseInsensitiveContains(q)
        }
    }

    /// Sections in order: each fitting category, then "Doesn't fit…".
    private var sections: [(title: String, color: Color, square: Color, entries: [Entry])] {
        let shown = visible
        var out: [(String, Color, Color, [Entry])] = []
        for category in Self.categories {
            let items = shown.filter { $0.fits && $0.kind.category == category }
            if !items.isEmpty {
                let tint = items[0].kind.tint
                out.append((category, tint, tint, items))
            }
        }
        let misfits = shown.filter { !$0.fits }
        if !misfits.isEmpty {
            let title = context.isStart ? "Doesn't fit as the first step"
                : context.input == .none ? "Doesn't fit after \(context.previous?.pickerName ?? "it")"
                : "Doesn't fit after \(context.input.rawValue)"
            out.append((title, Palette.fgMuted, Palette.comment, misfits))
        }
        return out
    }

    private var listHeight: CGFloat {
        let content = sections.reduce(CGFloat(6)) { $0 + Self.headerHeight + CGFloat($1.entries.count) * Self.rowHeight }
        let chrome: CGFloat = 76 + 37 + (context.branch != nil ? 38 : 0)
        return min(content, Self.maxHeight - chrome)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            if visible.isEmpty { noMatch } else { list }
            if context.branch != nil {
                Hairline()
                Text("Branches start from text, so Input blocks are hidden here.")
                    .font(VPFont.caption).foregroundStyle(Palette.fgMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.vertical, 10)
            }
            Hairline()
            footer
        }
        .frame(width: Self.width)
        .background(Palette.bg000)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.line, lineWidth: 1))
        .background(GeometryReader { geo in Color.clear.preference(key: PickerHeight.self, value: geo.size.height) })
        .onPreferenceChange(PickerHeight.self, perform: onHeight)
        .onAppear {
            if !initialQuery.isEmpty { query = initialQuery }
            highlighted = visible.first(where: \.fits)?.id ?? visible.first?.id
            filterFocused = true
        }
        .onChange(of: query) { _, _ in highlighted = visible.first(where: \.fits)?.id ?? visible.first?.id }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("", text: $query, prompt: Text("Filter blocks").foregroundStyle(Palette.fgMuted))
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .focused($filterFocused)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 4).fill(Palette.bg200))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.line, lineWidth: 1))
                .vpFocusRing(filterFocused)
                .onKeyPress(.downArrow) { move(1); return .handled }
                .onKeyPress(.upArrow) { move(-1); return .handled }
                .onKeyPress(.escape) { onClose(); return .handled }
                .onSubmit(addHighlighted)
                .accessibilityLabel("Filter blocks")
            contextLine.font(VPFont.caption).foregroundStyle(Palette.fgMuted).lineLimit(1)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
    }

    private var contextLine: Text {
        let gives = Text(context.input == .none ? "nothing" : context.input.rawValue).foregroundColor(Palette.fg)
        var line = Text("")
        if let branch = context.branch {
            line = Text("in branch ") + Text(branch).foregroundColor(Palette.purple) + Text(" · ")
        }
        guard let previous = context.previous else {
            return context.branch != nil ? line + Text("starts with ") + gives : Text("first step · starts the pipeline")
        }
        let name: String = switch previous {
        case .parakeet, .openRouterSTT: previous.chip
        default: previous.pickerName
        }
        let after = line + Text("after ") + Text(name).foregroundColor(previous.tint)
        return context.input == .none ? after + Text(" · ends the pipeline") : after + Text(" · gives ") + gives
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(sections, id: \.title) { section in
                        HStack(spacing: 6) {
                            Rectangle().fill(section.square).frame(width: 6, height: 6)
                            Text(section.title.uppercased()).font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1)
                                .foregroundStyle(section.color)
                        }
                        .padding(.horizontal, 12).padding(.top, 6)
                        .frame(height: Self.headerHeight, alignment: .leading)
                        ForEach(section.entries) { entry in row(entry).id(entry.id) }
                    }
                }
                .padding(.bottom, 6)
            }
            .scrollIndicators(.never)  // full-width rows (a legacy scroller would take a column); it still scrolls
            .frame(height: listHeight)
            .onChange(of: highlighted) { _, id in if let id { proxy.scrollTo(id) } }
        }
    }

    private func row(_ entry: Entry) -> some View {
        let on = highlighted == entry.id
        return Button { onAdd(entry.kind) } label: {
            HStack(spacing: 10) {
                Image(systemName: entry.kind.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(entry.kind.tint)
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 2).fill(entry.kind.tint.opacity(0.15)))
                VStack(alignment: .leading, spacing: 1) {
                    // The right-hand note sits on the name line, so the description gets the full width.
                    HStack(spacing: 8) {
                        Text(name(entry.kind.pickerName)).font(VPFont.bodyStrong).foregroundStyle(Palette.fg)
                        Spacer(minLength: 4)
                        trailing(entry)
                    }
                    Text(entry.kind.pickerDetail).font(VPFont.caption).foregroundStyle(Palette.fgMuted)
                        .lineLimit(1).truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .frame(height: Self.rowHeight)
            .background(on ? Palette.bg300 : .clear)
            // Inset past the panel's 1-pt border, which would otherwise cover half of the 2-pt edge.
            .overlay(alignment: .leading) { if on { Rectangle().fill(Palette.purple).frame(width: 2).padding(.leading, 1) } }
            .opacity(entry.fits ? 1 : 0.42)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { if $0 { highlighted = entry.id } }
        .accessibilityLabel("\(entry.kind.pickerName): \(entry.kind.pickerDetail)" + (entry.reason.map { ", \($0)" } ?? ""))
    }

    /// A misfit's reason, a missing key, or the types when they aren't text → text (most blocks).
    @ViewBuilder private func trailing(_ entry: Entry) -> some View {
        if let reason = entry.reason {
            Text(reason).font(VPFont.caption).foregroundStyle(Palette.orange).fixedSize()
        } else if let tag = entry.keyTag {
            KeyTag(text: tag)
                .fixedSize()
        } else if !(entry.kind.input == .text && entry.kind.output == .text) {
            Text("\(entry.kind.input.rawValue == "none" ? "—" : entry.kind.input.rawValue) → \(entry.kind.output.rawValue == "none" ? "—" : entry.kind.output.rawValue)")
                .font(VPFont.caption).foregroundStyle(Palette.fgMuted).fixedSize()
        }
    }

    /// The name with the filter's match underlined in purple.
    private func name(_ text: String) -> AttributedString {
        var out = AttributedString(text)
        let q = query.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty, let range = text.range(of: q, options: .caseInsensitive), let match = Range(range, in: out) {
            out[match].underlineStyle = Text.LineStyle(pattern: .solid, color: Palette.purple)
        }
        return out
    }

    private var noMatch: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No block called \"\(query)\"").font(VPFont.bodyStrong).foregroundStyle(Palette.fg)
            Text("To post somewhere, add an HTTP request and point it at the service's webhook.")
                .font(.system(size: 12, design: .monospaced)).lineSpacing(3).foregroundStyle(Palette.fgMuted)
                .fixedSize(horizontal: false, vertical: true)
            Button("Add HTTP request →") {
                if let http = StepKind.catalog.first(where: { if case .http = $0 { true } else { false } }) { onAdd(http) }
            }
            .buttonStyle(.plain).font(VPFont.bodyStrong).foregroundStyle(Palette.purple)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 18)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            keycap("↑↓"); Text("move")
            keycap("↩").padding(.leading, 4); Text("add")
            keycap("esc").padding(.leading, 4); Text("close")
            Spacer(minLength: 8)
            Text(query.trimmingCharacters(in: .whitespaces).isEmpty ? "\(entries.count) blocks" : "\(visible.count) of \(entries.count)")
        }
        .font(VPFont.caption).foregroundStyle(Palette.fgMuted)
        .padding(.horizontal, 12).frame(height: 36)
    }

    private func keycap(_ text: String) -> some View {
        Text(text).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(Palette.fg)
            .padding(.horizontal, 5).frame(height: 18)
            .background(RoundedRectangle(cornerRadius: 2).fill(Palette.bg300))
            .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Palette.line, lineWidth: 1))
    }

    private func move(_ delta: Int) {
        let ids = sections.flatMap { $0.entries.map(\.id) }
        guard !ids.isEmpty else { return }
        let current = highlighted.flatMap { ids.firstIndex(of: $0) } ?? -1
        highlighted = ids[max(0, min(ids.count - 1, current + delta))]
    }

    private func addHighlighted() {
        guard let id = highlighted, let entry = visible.first(where: { $0.id == id }) else {
            if visible.isEmpty, let http = StepKind.catalog.first(where: { if case .http = $0 { true } else { false } }) { onAdd(http) }
            return
        }
        onAdd(entry.kind)
    }
}

private struct PickerHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// A picker's window: borderless, with the window shadow, attached to the editor and placed under the control
/// that opened it (above it near the bottom of the screen). It takes the keyboard while open; clicking anywhere
/// else, Esc or a pick closes it. Shared by the Add step picker and the model pickers.
@MainActor
final class AnchoredPanel {
    static let shared = AnchoredPanel()
    private var panel: NSPanel?
    private var resignObserver: NSObjectProtocol?
    private var anchorRect: NSRect = .zero
    private var above = false
    private var width: CGFloat = 400
    private var maxHeight: CGFloat = 520

    /// `content` gets `close` and `reportHeight` (call it with the content's height so the panel fits it).
    func show<Content: View>(from anchor: NSView, width: CGFloat, maxHeight: CGFloat,
                             @ViewBuilder content: (_ close: @escaping () -> Void, _ reportHeight: @escaping (CGFloat) -> Void) -> Content) {
        close()
        guard let window = anchor.window else { return }
        self.width = width
        self.maxHeight = maxHeight
        anchorRect = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let panel = PickerPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: 300),
                                styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.appearance = window.effectiveAppearance
        let view = content({ [weak self] in self?.close() }, { [weak self] height in self?.place(height: height) })
        let host = NSHostingView(rootView: view.vpWindow())
        panel.contentView = host
        self.panel = panel
        place(height: host.fittingSize.height)
        window.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    /// Below the control, top edge fixed as the content shrinks; above it if there's no room below.
    private func place(height: CGFloat) {
        guard let panel, height > 0 else { return }
        let screen = NSScreen.screens.first { $0.frame.intersects(anchorRect) }?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        if panel.frame.height < 10 || !panel.isVisible { above = anchorRect.minY - 4 - maxHeight < screen.minY }
        let x = min(max(anchorRect.minX - 4, screen.minX + 8), screen.maxX - width - 8)
        let y = above ? anchorRect.maxY + 4 : anchorRect.minY - 4 - height
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        panel.invalidateShadow()
    }

    func close() {
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        guard let panel else { return }
        self.panel = nil
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }
}

/// The Add step picker in its panel.
@MainActor
enum StepPickerPanel {
    static func show(from anchor: NSView, context: StepPickerContext, onAdd: @escaping (StepKind) -> Void) {
        AnchoredPanel.shared.show(from: anchor, width: StepPicker.width, maxHeight: StepPicker.maxHeight) { close, report in
            StepPicker(context: context, onAdd: { kind in
                onAdd(kind)
                close()
            }, onClose: close, onHeight: report)
        }
    }
}

private final class PickerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Finds the NSView behind a SwiftUI view, to place a window next to it.
struct AnchorView: NSViewRepresentable {
    let onResolve: (NSView) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onResolve(view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
