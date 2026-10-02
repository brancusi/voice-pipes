import AppKit
import SwiftUI

/// A small, translucent status tag at the bottom of the screen, with the answering model on a line under it. It
/// ignores the mouse except while reading aloud (for its pause and stop buttons), never takes focus from the app
/// you're in, and fades out as soon as a run is done.
@MainActor
final class HUDController {
    private var panel: HUDPanel?
    private var tracker: PointerTracker?
    private weak var app: AppState?
    static let size = NSSize(width: 520, height: 66)
    /// With the read-along card open above the tag.
    static let expandedHeight: CGFloat = 340

    func attach(_ app: AppState) {
        self.app = app
        observe()
    }

    private func observe() {
        guard let app else { return }
        let (visible, speaking, expanded) = withObservationTracking {
            (app.run != nil, app.run?.phase == .speaking, HUDView.expanded(app))
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
        self.expanded = expanded
        visible ? show() : hide()
        // Clickable only while its buttons are showing; otherwise clicks go straight through.
        panel?.ignoresMouseEvents = !speaking
        // The keyboard while reading: taken at once in "always" mode; given back when the reading ends.
        if speaking != wasSpeaking {
            wasSpeaking = speaking
            app.setReadingShortcuts(speaking)
            if speaking, app.store.reading.takeKeys == .always { takeKeys(.reading) } else if !speaking { releaseKeys() }
        }
    }

    // MARK: The keyboard while reading

    private var wasSpeaking = false
    private var keysReason: HUDKeys.Reason?
    /// The app you were in, to give the keys back to.
    private weak var previousApp: NSRunningApplication?
    private var pointerAtShow: NSPoint?
    private var releasing = false

    private var reading: ReadingSettings { app?.store.reading ?? ReadingSettings() }
    private var isSpeaking: Bool { app?.run?.phase == .speaking }

    /// Makes the HUD the key window without activating Voice Pipes: the app you're in stays in front.
    private func takeKeys(_ reason: HUDKeys.Reason) {
        guard let panel, isSpeaking, reading.takeKeys != .never else { return }
        if keysReason == nil || reason != .hover { keysReason = reason }
        guard !panel.isKeyWindow else { return }
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp = front }
        panel.acceptsKeys = true
        panel.makeKey()
        HUDKeys.shared.active = true
    }

    /// Gives the keyboard back to the app you were in.
    private func releaseKeys() {
        guard let panel else { return }
        keysReason = nil
        HUDKeys.shared.active = false
        guard panel.isKeyWindow else { panel.acceptsKeys = false; return }
        releasing = true
        panel.acceptsKeys = false
        if let previousApp, !previousApp.isTerminated {
            previousApp.activate()
        } else {
            NSApp.mainWindow?.makeKey()
        }
    }

    /// Clicking elsewhere took the keys: maybe stop the reading too (Setup → Reading).
    private func keysResigned() {
        let ours = releasing
        releasing = false
        panel?.acceptsKeys = false
        keysReason = nil
        HUDKeys.shared.active = false
        if !ours, isSpeaking, reading.clickAway == .stop { app?.speaker.clear() }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard HUDKeys.shared.active else { return false }
        // A ⌘ shortcut isn't for the HUD (and must never reach Voice Pipes' menu, ⌘Q): give the keys back.
        if event.modifierFlags.contains(.command) {
            releaseKeys()
            return true
        }
        if let action = reading.action(for: event) { app?.readingAction(action) }
        return true  // other keys are swallowed while the HUD has the keyboard, rather than beeping
    }

    private func pointerMoved(inside: Bool) {
        guard reading.takeKeys == .hover || reading.takeKeys == .always else { return }
        if inside {
            // Only when the pointer moves onto it: the card appearing under a resting pointer doesn't count.
            guard NSEvent.mouseLocation != pointerAtShow else { return }
            takeKeys(.hover)
        } else if keysReason == .hover {
            releaseKeys()
        }
    }

    private var expanded = false
    private weak var screen: NSScreen?

    private func show() {
        guard let app else { return }
        let panel = self.panel ?? makePanel(app)
        let appearing = !(panel.isVisible && panel.alphaValue > 0)
        self.panel = panel
        // Pick the screen when the HUD appears; opening the card later grows it upwards on the same screen.
        if appearing || screen == nil {
            screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        }
        if let frame = screen?.visibleFrame {
            let height = expanded ? Self.expandedHeight : Self.size.height
            panel.setFrame(NSRect(x: frame.midX - Self.size.width / 2, y: frame.minY + 14,
                                  width: Self.size.width, height: height), display: true)
        }
        if appearing { pointerAtShow = NSEvent.mouseLocation }
        panel.alphaValue = 1
        panel.orderFrontRegardless()
    }

    private func hide() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 0
        } completionHandler: {
            Task { @MainActor in
                // A new run may have started during the fade.
                if self.app?.run == nil { panel.orderOut(nil) }
            }
        }
    }

    private func makePanel(_ app: AppState) -> HUDPanel {
        let panel = HUDPanel(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless],
                             backing: .buffered, defer: false)
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let host = FirstClickHostingView(rootView: HUDView(app: app))
        panel.contentView = host
        panel.onKey = { [weak self] event in self?.handleKey(event) ?? false }
        panel.onClick = { [weak self] in
            guard let self, self.reading.takeKeys != .never else { return }
            self.takeKeys(.click)
        }
        // Tracks the pointer even though Voice Pipes isn't the active app (SwiftUI's hover only works when it is).
        let tracker = PointerTracker { [weak self] inside in self?.pointerMoved(inside: inside) }
        self.tracker = tracker
        host.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                            owner: tracker))
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.keysResigned() }
        }
        return panel
    }
}

/// Never main, and key only while it has taken the keys for a reading (a non-activating panel, so the app you're
/// in stays the active app). Key presses and clicks go to the controller first.
private final class HUDPanel: NSPanel {
    var acceptsKeys = false
    var onKey: ((NSEvent) -> Bool)?
    var onClick: (() -> Void)?

    override var canBecomeKey: Bool { acceptsKeys }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, onKey?(event) == true { return }
        if event.type == .leftMouseDown { onClick?() }
        super.sendEvent(event)
    }
}

/// Whether the HUD has the keyboard, for its "keys on" marker.
@MainActor @Observable
final class HUDKeys {
    static let shared = HUDKeys()
    enum Reason { case reading, hover, click }
    var active = false
}

/// Enter/exit/move over the HUD, delivered even while another app is active.
private final class PointerTracker: NSObject {
    let onChange: (Bool) -> Void
    private var inside = false
    init(onChange: @escaping (Bool) -> Void) { self.onChange = onChange }
    @objc func mouseEntered(with event: NSEvent) { inside = true; onChange(true) }
    @objc func mouseMoved(with event: NSEvent) { if inside { onChange(true) } }
    @objc func mouseExited(with event: NSEvent) { inside = false; onChange(false) }
}

/// Buttons respond to the first click even though the HUD is never the active window.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct HUDView: View {
    let app: AppState

    /// The read-along card shows while something is being read and the card is open.
    static func expanded(_ app: AppState) -> Bool {
        app.readAlong && app.run?.phase == .speaking && !app.speaker.sentences.isEmpty
    }

    /// "Esc stop · Space pause · J/K sentence · H/L speed" with the keys in fg and the words muted.
    static func keysHintText(_ reading: ReadingSettings) -> Text {
        keysHint(reading).components(separatedBy: " · ").enumerated().reduce(Text("")) { text, item in
            let parts = item.element.split(separator: " ", maxSplits: 1).map(String.init)
            let piece = Text(parts.first ?? "").foregroundColor(Palette.hudFG)
                + Text(parts.count > 1 ? " " + parts[1] : "").foregroundColor(Palette.hudMuted)
            return item.offset == 0 ? piece : text + Text(" · ").foregroundColor(Palette.hudMuted) + piece
        }
    }

    /// "Esc stop · Space pause · J/K sentence · H/L speed", from the keys you've set (first key of each).
    static func keysHint(_ reading: ReadingSettings) -> String {
        func key(_ action: ReadingSettings.Action) -> String? { reading.keys[action]?.first?.display }
        func pair(_ a: ReadingSettings.Action, _ b: ReadingSettings.Action) -> String? {
            guard let x = key(a), let y = key(b) else { return key(a) ?? key(b) }
            return "\(x)/\(y)"
        }
        return [key(.stop).map { "\($0) stop" }, key(.pause).map { "\($0) pause" },
                pair(.next, .previous).map { "\($0) sentence" }, pair(.slower, .faster).map { "\($0) speed" }]
            .compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        let expanded = Self.expanded(app)
        VStack(spacing: 6) {
            Spacer(minLength: 0)
            if expanded {
                ReadAlongCard(speaker: app.speaker, keysHint: Self.keysHintText(app.store.reading))
                    .frame(height: HUDController.expandedHeight - HUDController.size.height - 6)
                    .transition(.opacity)
            }
            if let run = app.run {
                VStack(spacing: 3) {
                    content(run)
                    if let info = run.modelInfo, run.phase != .recording { ModelLine(text: info) }
                }
                .transition(.opacity)
            }
        }
        .frame(width: HUDController.size.width, height: expanded ? HUDController.expandedHeight : HUDController.size.height)
        .animation(.easeOut(duration: 0.15), value: app.run?.phase)
    }

    @ViewBuilder private func content(_ run: ActiveRun) -> some View {
        switch run.phase {
        case .recording:
            // Streaming and chunked transcription show the words as they land, with a cursor; otherwise the level.
            TimelineView(.periodic(from: run.recordingStarted, by: 1)) { context in
                HUDTag(state: .recording, label: "REC",
                       detail: HUDTag.clock(context.date.timeIntervalSince(run.recordingStarted)),
                       level: run.liveText.isEmpty ? run.level : nil,
                       liveText: run.liveText.isEmpty ? nil : run.liveText)
            }
        case .processing:
            TimelineView(.animation(minimumInterval: 0.05)) { context in
                HUDTag(state: .processing, label: "PROC", detail: HUDTag.ms(context.date.timeIntervalSince(run.processingStarted)))
            }
        case .speaking:
            let speaker = app.speaker
            let controls = PlaybackControls(paused: speaker.state == .paused, canPause: speaker.state != .loading,
                                            onToggle: speaker.togglePause, onStop: speaker.clear,
                                            expanded: app.readAlong, onExpand: { app.readAlong.toggle() })
            switch speaker.state {
            case .loading: HUDTag(state: .speaking, label: "VOICE", detail: "···", controls: controls)
            case .paused: HUDTag(state: .paused, label: "PAUSED", detail: "\(Int(speaker.progress * 100))%", controls: controls)
            default: HUDTag(state: .speaking, label: "READ", detail: "\(Int(speaker.progress * 100))%", controls: controls)
            }
        case .done:
            HUDTag(state: .done, label: "OK", detail: run.totalMs.map { HUDTag.ms(Double($0) / 1000) })
        case .failed(let message):
            HUDTag(state: .failed, label: "ERR", detail: message)
        }
    }
}

/// The tag itself: a colored square, a label and one detail, in monospace on a dark translucent strip.
struct HUDTag: View {
    enum State { case recording, processing, speaking, paused, done, failed }

    let state: State
    let label: String
    var detail: String?
    var level: Float?
    /// Dictation so far (streaming modes), shown with its tail visible and a sage cursor.
    var liveText: String?
    var controls: PlaybackControls?

    var body: some View {
        HStack(spacing: 7) {
            Rectangle().fill(color).frame(width: 7, height: 7)
            Text(label).foregroundStyle(Palette.hudFG)
            if let detail { Text(detail).foregroundStyle(Palette.hudMuted).truncationMode(.tail) }
            if let level { Meter(level: level) }
            if let liveText {
                Text(liveText).foregroundStyle(Palette.hudFG).truncationMode(.head).frame(maxWidth: 260, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                BlinkingCursor()
            }
            if let controls { controls.padding(.leading, 2) }
            if controls != nil, HUDKeys.shared.active {
                Text("KEYS").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(Color(hex: 0xC3A3D4))
                    .padding(.horizontal, 5).frame(height: 16)
                    .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Color(hex: 0xC3A3D4), lineWidth: 1))
                    .help("The HUD has the keyboard; Esc stops, move away or click elsewhere to give it back")
            }
        }
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .tracking(0.4)
        .lineLimit(1)
        .padding(.horizontal, 9)
        .frame(height: 22)
        .background(
            RoundedRectangle(cornerRadius: 2)
                .fill(Palette.hudBG)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 2))
        )
        .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Palette.hudFG.opacity(0.14), lineWidth: 0.5))
        .environment(\.colorScheme, .dark)
        .frame(maxWidth: HUDController.size.width - 20)
    }

    private var color: Color {
        switch state {
        case .recording: Color(hex: 0xE0694A)
        case .processing: Color(hex: 0xE8C26A)
        case .speaking: Color(hex: 0xC3A3D4)
        case .paused: Palette.hudMuted
        case .done: Color(hex: 0xA9BF8A)
        case .failed: Color(hex: 0xF0A35E)
        }
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    static func ms(_ seconds: TimeInterval) -> String {
        seconds < 10 ? "\(Int(seconds * 1000))ms" : String(format: "%.1fs", seconds)
    }
}

/// Pause/resume and stop for read-aloud, inside the HUD tag.
struct PlaybackControls: View {
    let paused: Bool
    let canPause: Bool
    let onToggle: () -> Void
    let onStop: () -> Void
    var expanded = false
    var onExpand: (() -> Void)?

    var body: some View {
        HStack(spacing: 2) {
            button(paused ? "play.fill" : "pause.fill", help: paused ? "Resume" : "Pause", action: onToggle)
                .disabled(!canPause)
            button("stop.fill", help: "Stop", action: onStop)
            if let onExpand {
                button(expanded ? "chevron.down" : "text.alignleft", help: expanded ? "Hide the text" : "Follow along: show the text and speed",
                       action: onExpand)
            }
        }
    }

    private func button(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .frame(width: 20, height: 16)
                .background(RoundedRectangle(cornerRadius: 2).fill(Palette.hudFG.opacity(0.14)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.hudFG)
        .help(help)
    }
}

/// The model answering this run (and the route Jev picked), on a quieter line under the tag.
struct ModelLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .regular, design: .monospaced))
            .foregroundStyle(Palette.hudMuted)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 7)
            .frame(height: 17)
            .background(RoundedRectangle(cornerRadius: 2).fill(Palette.hudBG))
            .environment(\.colorScheme, .dark)
            .frame(maxWidth: HUDController.size.width - 20)
    }
}

/// Five thin bars for the input level.
private struct Meter: View {
    let level: Float

    var body: some View {
        HStack(alignment: .center, spacing: 1.5) {
            ForEach(0..<5, id: \.self) { i in
                Rectangle()
                    .fill(Palette.hudFG.opacity(level > Float(i) / 5 ? 1 : 0.25))
                    .frame(width: 2, height: 4 + CGFloat(i % 3) * 2.5)
            }
        }
    }
}

/// The live-text cursor: a sage ▌, 530 ms on and 530 ms off; solid under Reduce Motion.
private struct BlinkingCursor: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.53)) { context in
            let on = reduceMotion || Int(context.date.timeIntervalSinceReferenceDate / 0.53) % 2 == 0
            Text("▌").foregroundStyle(Color(hex: 0xA9BF8A)).opacity(on ? 1 : 0)
        }
        .accessibilityHidden(true)
    }
}

extension Collection {
    subscript(safe index: Index) -> Element? { indices.contains(index) ? self[index] : nil }
}

extension Color {
    init(hex: String) {
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x0A66D8
        self.init(red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }
}

/// Above the HUD while reading aloud: the whole text a sentence per line, the one being read lit with a lavender
/// bar (finished ones dimmed), following the voice. Hover to look ahead (following pauses until the pointer
/// leaves); the speed changes live.
struct ReadAlongCard: View {
    let speaker: Speaker
    var keysHint = Text("")
    @State private var hovering = false
    private static let lavender = Color(hex: 0xC3A3D4)

    var body: some View {
        let current = speaker.currentSentence
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(speaker.sentences) { sentence in
                            SentenceRow(sentence: sentence, current: current, position: speaker.position,
                                        tint: Self.lavender) { speaker.seek(toSentence: sentence.id) }
                                .padding(.top, sentence.opensParagraph ? 7 : 0)
                                .id(sentence.id)
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 22)
                }
                .scrollIndicators(.never)
                // Lines fade at the card's top and bottom edges instead of being cut mid-glyph.
                .mask(
                    // 24 pt from transparent at each edge to opaque, on the scrolling text itself.
                    VStack(spacing: 0) {
                        LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 24)
                        Rectangle().fill(.black)
                        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 24)
                    }
                )
                .onHover { hovering = $0 }
                .onAppear { proxy.scrollTo(current, anchor: UnitPoint(x: 0, y: 0.3)) }
                .onChange(of: current) { _, new in follow(proxy, to: new) }
                .onChange(of: hovering) { _, now in if !now { follow(proxy, to: current) } }
            }
            Rectangle().fill(Palette.hudFG.opacity(0.1)).frame(height: 0.5)
            HStack(spacing: 8) {
                if HUDKeys.shared.active {
                    // The HUD has the keyboard: say so (never truncated), and which keys do what (truncates).
                    Text("KEYS ON").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(Self.lavender)
                        .fixedSize()
                    keysHint.lineLimit(1).truncationMode(.tail)
                } else {
                    Text(hovering ? "click a sentence to read from there" : speaker.voiceLabel)
                        .foregroundStyle(Palette.hudMuted).lineLimit(1).truncationMode(.tail)
                }
                Spacer(minLength: 6)
                speedButton("minus", help: "Slower") { speaker.setRate(speaker.rate - 0.1) }
                    .disabled(speaker.rate <= 0.6)
                Text(String(format: "%.1f×", speaker.rate)).foregroundStyle(Palette.hudFG).monospacedDigit().frame(width: 34)
                speedButton("plus", help: "Faster") { speaker.setRate(speaker.rate + 0.1) }
                    .disabled(speaker.rate >= 2)
            }
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .padding(.horizontal, 10).frame(height: 26)
        }
        .font(.system(size: 12, design: .monospaced))
        .background(
            RoundedRectangle(cornerRadius: 2)
                .fill(Palette.hudBG)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 2))
        )
        .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Palette.hudFG.opacity(0.14), lineWidth: 0.5))
        .environment(\.colorScheme, .dark)
        .frame(width: HUDController.size.width - 20)
    }

    private func follow(_ proxy: ScrollViewProxy, to sentence: Int) {
        guard !hovering else { return }
        withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(sentence, anchor: UnitPoint(x: 0, y: 0.3)) }
    }

    private func speedButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .frame(width: 20, height: 16)
                .background(RoundedRectangle(cornerRadius: 2).fill(Palette.hudFG.opacity(0.14)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.hudFG)
        .help(help)
    }
}

/// One sentence in the read-along card; click to read from it. The one being read is lit with a bar; inside it,
/// what's been read is full brightness and the word being spoken has a thin underline that runs along with the voice.
private struct SentenceRow: View {
    let sentence: Speaker.Sentence
    let current: Int
    let position: Int
    let tint: Color
    let onTap: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Rectangle().fill(sentence.id == current ? tint : .clear).frame(width: 2)
            text
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 1)
        .background(RoundedRectangle(cornerRadius: 2).fill(Palette.hudFG.opacity(hovering ? 0.07 : 0)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: onTap)
        .help("Read from here")
    }

    private var text: Text {
        if sentence.id < current { return Text(sentence.text).foregroundColor(Palette.hudMuted.opacity(0.45)) }
        guard sentence.id == current else { return Text(sentence.text).foregroundColor(Palette.hudFG.opacity(0.7)) }
        return Text(Self.marked(sentence.text, at: position - sentence.start, tint: tint))
    }

    /// Read part bright, the rest a little softer, the word at `offset` (UTF-16, within the sentence) underlined.
    static func marked(_ text: String, at offset: Int, tint: Color) -> AttributedString {
        var out = AttributedString(text)
        out.foregroundColor = Palette.hudFG.opacity(0.82)
        let utf16 = text.utf16
        let clamped = min(max(0, offset), utf16.count)
        // On a character boundary (an offset inside an emoji or accent falls back to the character it's in).
        guard let cursor = String.Index(utf16.index(utf16.startIndex, offsetBy: clamped), within: text)
                ?? text.indices.last(where: { $0.utf16Offset(in: text) <= clamped }) else { return out }
        // The word around the cursor: back to the last space, on to the next.
        var wordStart = cursor
        while wordStart > text.startIndex, !text[text.index(before: wordStart)].isWhitespace { wordStart = text.index(before: wordStart) }
        var wordEnd = cursor
        while wordEnd < text.endIndex, !text[wordEnd].isWhitespace { wordEnd = text.index(after: wordEnd) }
        if let read = Range(text.startIndex..<wordEnd, in: out) { out[read].foregroundColor = Palette.hudFG }
        if wordStart < wordEnd, let word = Range(wordStart..<wordEnd, in: out) {
            out[word].underlineStyle = Text.LineStyle(pattern: .solid, color: tint.opacity(0.85))
        }
        return out
    }
}
