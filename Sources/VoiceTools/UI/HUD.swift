import AppKit
import SwiftUI

/// Floating, non-activating panel at the bottom of the screen that shows the running track.
@MainActor
final class HUDController {
    private var panel: NSPanel?
    private weak var app: AppState?

    func attach(_ app: AppState) {
        self.app = app
        observe()
    }

    private func observe() {
        guard let app else { return }
        let visible = withObservationTracking { app.run != nil } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
        visible ? show() : panel?.orderOut(nil)
    }

    private func show() {
        guard let app else { return }
        let panel = self.panel ?? makePanel(app)
        self.panel = panel
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            let size = NSSize(width: 480, height: 150)
            panel.setFrame(NSRect(x: frame.midX - size.width / 2, y: frame.minY + 40,
                                  width: size.width, height: size.height), display: true)
        }
        panel.orderFrontRegardless()
    }

    private func makePanel(_ app: AppState) -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless],
                            backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
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
                card(run)
            }
        }
        .frame(width: 480, height: 150)
    }

    private func card(_ run: ActiveRun) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                indicator(run)
                Text(run.trackName).font(.system(size: 13, weight: .semibold))
                Text(subtitle(run)).font(.system(size: 12)).foregroundStyle(.white.opacity(0.7))
                Spacer()
                if run.phase == .recording {
                    LevelMeter(level: run.level, color: Color(hex: run.colorHex))
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(Duration.seconds(Date().timeIntervalSince(run.recordingStarted)),
                             format: .time(pattern: .minuteSecond))
                            .font(.system(size: 13).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
            }
            if case .failed(let message) = run.phase {
                Text(message).font(.system(size: 13)).foregroundStyle(Color(red: 1, green: 0.55, blue: 0.5))
                    .lineLimit(2)
            } else if !run.liveText.isEmpty {
                Text(run.liveText).font(.system(size: 14)).lineLimit(2).truncationMode(.head)
            }
            if run.phase != .recording {
                StepBar(run: run)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 22).fill(Color(white: 0.11).opacity(0.92)))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.1)))
    }

    @ViewBuilder private func indicator(_ run: ActiveRun) -> some View {
        switch run.phase {
        case .recording:
            Circle().fill(Color.red).frame(width: 10, height: 10)
        case .processing:
            ProgressView().controlSize(.small).tint(.white)
        case .speaking:
            Image(systemName: app.speaker.state == .paused ? "pause.fill" : "speaker.wave.2.fill")
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }

    private func subtitle(_ run: ActiveRun) -> String {
        switch run.phase {
        case .recording: run.heldBy.map { "\($0)" } ?? "recording"
        case .processing: run.stepTitles[safe: run.currentStep] ?? ""
        case .speaking: app.speaker.state == .paused ? "paused" : "speaking"
        case .done:
            "\(run.stepMs.compactMap { $0 }.dropFirst().reduce(0, +)) ms"
        case .failed: "failed"
        }
    }
}

private struct StepBar: View {
    let run: ActiveRun

    var body: some View {
        HStack(spacing: 6) {
            ForEach(run.stepTitles.indices.dropFirst(), id: \.self) { i in
                VStack(alignment: .leading, spacing: 4) {
                    Capsule().fill(fill(i)).frame(height: 4)
                    HStack {
                        Text(run.stepTitles[i]).lineLimit(1)
                        Spacer(minLength: 2)
                        if let ms = run.stepMs[i] { Text("\(ms) ms").monospacedDigit() }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.75))
                }
            }
        }
    }

    private func fill(_ i: Int) -> Color {
        let accent = Color(hex: run.colorHex)
        if run.stepMs[i] != nil { return accent }
        if i == run.currentStep { return accent.opacity(0.45) }
        return .white.opacity(0.2)
    }
}

private struct LevelMeter: View {
    let level: Float
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<14, id: \.self) { i in
                let threshold = Float(i) / 14
                Capsule().fill(level > threshold ? color : .white.opacity(0.2))
                    .frame(width: 3, height: 6 + CGFloat(i % 5) * 3)
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
