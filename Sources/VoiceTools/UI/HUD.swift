import AppKit
import SwiftUI

/// A small, translucent status tag at the bottom of the screen. It ignores the mouse, so it never gets in the way,
/// and fades out as soon as a run is done.
@MainActor
final class HUDController {
    private var panel: NSPanel?
    private weak var app: AppState?
    static let size = NSSize(width: 520, height: 44)

    func attach(_ app: AppState) {
        self.app = app
        observe()
    }

    private func observe() {
        guard let app else { return }
        let visible = withObservationTracking { app.run != nil } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
        visible ? show() : hide()
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
        let panel = NSPanel(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless],
                            backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: HUDView(app: app))
        return panel
    }
}

struct HUDView: View {
    let app: AppState

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            if let run = app.run {
                content(run).transition(.opacity)
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
            switch app.speaker.state {
            case .loading: HUDTag(state: .speaking, label: "VOICE", detail: "···")
            case .paused: HUDTag(state: .paused, label: "PAUSED", detail: "\(Int(app.speaker.progress * 100))%")
            default: HUDTag(state: .speaking, label: "READ", detail: "\(Int(app.speaker.progress * 100))%")
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

    var body: some View {
        HStack(spacing: 7) {
            Rectangle().fill(color).frame(width: 7, height: 7)
            Text(label).foregroundStyle(.white.opacity(0.92))
            if let detail { Text(detail).foregroundStyle(.white.opacity(0.6)).truncationMode(.tail) }
            if let level { Meter(level: level) }
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
