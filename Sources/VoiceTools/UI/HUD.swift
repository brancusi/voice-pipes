import AppKit
import SwiftUI

/// A small, translucent status tag at the bottom of the screen, with the answering model on a line under it. It
/// ignores the mouse except while reading aloud (for its pause and stop buttons), never takes focus from the app
/// you're in, and fades out as soon as a run is done.
@MainActor
final class HUDController {
    private var panel: NSPanel?
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

    private func makePanel(_ app: AppState) -> NSPanel {
        let panel = HUDPanel(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless],
                             backing: .buffered, defer: false)
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = FirstClickHostingView(rootView: HUDView(app: app))
        return panel
    }
}

/// Never key or main, so clicking the HUD leaves the keyboard focus in the app you were using.
private final class HUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
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

    var body: some View {
        let expanded = Self.expanded(app)
        VStack(spacing: 6) {
            Spacer(minLength: 0)
            if expanded {
                ReadAlongCard(speaker: app.speaker)
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
    @State private var hovering = false
    private static let lavender = Color(hex: 0xC3A3D4)

    var body: some View {
        let current = speaker.currentSentence
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(speaker.sentences) { sentence in
                            HStack(alignment: .top, spacing: 8) {
                                Rectangle().fill(sentence.id == current ? Self.lavender : .clear).frame(width: 2)
                                Text(sentence.text)
                                    .foregroundStyle(sentence.id == current ? Palette.hudFG
                                                     : sentence.id < current ? Palette.hudMuted.opacity(0.45) : Palette.hudFG.opacity(0.7))
                                    .lineSpacing(3)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.top, sentence.opensParagraph ? 7 : 0)
                            .id(sentence.id)
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                }
                .scrollIndicators(.never)
                .onHover { hovering = $0 }
                .onAppear { proxy.scrollTo(current, anchor: UnitPoint(x: 0, y: 0.3)) }
                .onChange(of: current) { _, new in follow(proxy, to: new) }
                .onChange(of: hovering) { _, now in if !now { follow(proxy, to: current) } }
            }
            Rectangle().fill(Palette.hudFG.opacity(0.1)).frame(height: 0.5)
            HStack(spacing: 8) {
                Text(hovering ? "looking ahead · follows again when the pointer leaves" : speaker.voiceLabel)
                    .foregroundStyle(Palette.hudMuted).lineLimit(1).truncationMode(.tail)
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
