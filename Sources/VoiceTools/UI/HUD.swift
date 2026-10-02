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

    func attach(_ app: AppState) {
        self.app = app
        observe()
    }

    private func observe() {
        guard let app else { return }
        let (visible, speaking) = withObservationTracking {
            (app.run != nil, app.run?.phase == .speaking)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
        visible ? show() : hide()
        // Clickable only while its buttons are showing; otherwise clicks go straight through.
        panel?.ignoresMouseEvents = !speaking
    }

    private func show() {
        guard let app else { return }
        let panel = self.panel ?? makePanel(app)
        self.panel = panel
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrame(NSRect(x: frame.midX - Self.size.width / 2, y: frame.minY + 14,
                                  width: Self.size.width, height: Self.size.height), display: true)
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

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            if let run = app.run {
                VStack(spacing: 3) {
                    content(run)
                    if let info = run.modelInfo, run.phase != .recording { ModelLine(text: info) }
                }
                .transition(.opacity)
            }
        }
        .frame(width: HUDController.size.width, height: HUDController.size.height)
        .animation(.easeOut(duration: 0.15), value: app.run?.phase)
    }

    @ViewBuilder private func content(_ run: ActiveRun) -> some View {
        switch run.phase {
        case .recording:
            TimelineView(.periodic(from: run.recordingStarted, by: 1)) { context in
                HUDTag(state: .recording, label: "REC",
                       detail: HUDTag.clock(context.date.timeIntervalSince(run.recordingStarted)), level: run.level)
            }
        case .processing:
            TimelineView(.animation(minimumInterval: 0.05)) { context in
                HUDTag(state: .processing, label: "PROC", detail: HUDTag.ms(context.date.timeIntervalSince(run.processingStarted)))
            }
        case .speaking:
            let speaker = app.speaker
            let controls = PlaybackControls(paused: speaker.state == .paused, canPause: speaker.state != .loading,
                                            onToggle: speaker.togglePause, onStop: speaker.clear)
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
    var controls: PlaybackControls?

    var body: some View {
        HStack(spacing: 7) {
            Rectangle().fill(color).frame(width: 7, height: 7)
            Text(label).foregroundStyle(.white.opacity(0.92))
            if let detail { Text(detail).foregroundStyle(.white.opacity(0.6)).truncationMode(.tail) }
            if let level { Meter(level: level) }
            if let controls { controls.padding(.leading, 2) }
        }
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .tracking(0.4)
        .lineLimit(1)
        .padding(.horizontal, 9)
        .frame(height: 22)
        .background(
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(.black.opacity(0.45))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 2.5, style: .continuous))
        )
        .overlay(RoundedRectangle(cornerRadius: 2.5, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
        .environment(\.colorScheme, .dark)
        .frame(maxWidth: HUDController.size.width - 20)
    }

    private var color: Color {
        switch state {
        case .recording: Color(red: 1, green: 0.27, blue: 0.23)
        case .processing: Color(red: 1, green: 0.75, blue: 0.2)
        case .speaking: Color(red: 0.62, green: 0.55, blue: 1)
        case .paused: .white.opacity(0.45)
        case .done: Color(red: 0.2, green: 0.85, blue: 0.45)
        case .failed: Color(red: 1, green: 0.55, blue: 0.2)
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

    var body: some View {
        HStack(spacing: 2) {
            button(paused ? "play.fill" : "pause.fill", help: paused ? "Resume" : "Pause", action: onToggle)
                .disabled(!canPause)
            button("stop.fill", help: "Stop", action: onStop)
        }
    }

    private func button(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .frame(width: 20, height: 16)
                .background(RoundedRectangle(cornerRadius: 2).fill(.white.opacity(0.14)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.9))
        .help(help)
    }
}

/// The model answering this run (and the route Jev picked), on a quieter line under the tag.
private struct ModelLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .regular, design: .monospaced))
            .foregroundStyle(.white.opacity(0.75))
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 7)
            .frame(height: 17)
            .background(RoundedRectangle(cornerRadius: 2.5, style: .continuous).fill(.black.opacity(0.4)))
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
                    .fill(.white.opacity(level > Float(i) / 5 ? 0.85 : 0.2))
                    .frame(width: 2, height: 4 + CGFloat(i % 3) * 2.5)
            }
        }
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
