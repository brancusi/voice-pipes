import SwiftUI

struct MenuView: View {
    @Bindable var app: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            section("Tracks") { tracks }
            if app.speaker.state != .idle { section("Now playing") { nowPlaying } }
            if !app.history.isEmpty { section("Recent runs") { recent } }
            HStack {
                Button("Edit tracks…") { openEditor() }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.link)
            .font(.system(size: 12))
        }
        .padding(14)
        .frame(width: 400)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Voice Tools").font(.system(size: 15, weight: .semibold))
                HStack(spacing: 6) {
                    Circle().fill(statusColor).frame(width: 7, height: 7)
                    Text(statusText).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button { openEditor() } label: { Image(systemName: "slider.horizontal.3") }
                .buttonStyle(.borderless)
                .help("Edit tracks")
        }
    }

    private var tracks: some View {
        VStack(spacing: 0) {
            ForEach(Array(app.store.tracks.enumerated()), id: \.element.id) { index, track in
                if index > 0 { Divider() }
                Button { app.start(track) } label: { TrackRow(track: track) }
                    .buttonStyle(.plain)
                    .opacity(track.enabled ? 1 : 0.45)
            }
        }
        .card()
    }

    private var nowPlaying: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(app.speaker.state == .paused ? "Paused" : "Speaking")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(Color.orange.opacity(0.18)))
                Text(app.speaker.sourceLabel).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
            }
            ProgressView(value: app.speaker.progress)
            HStack {
                Button(app.speaker.state == .paused ? "Resume" : "Pause") { app.speaker.togglePause() }
                    .buttonStyle(.borderedProminent)
                Button("Clear") { app.speaker.clear() }
            }
        }
        .padding(12)
        .card()
    }

    private var recent: some View {
        VStack(spacing: 0) {
            ForEach(Array(app.history.prefix(5).enumerated()), id: \.element.id) { index, record in
                if index > 0 { Divider() }
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(record.trackName) · \(record.date.formatted(.relative(presentation: .named))) · \(record.totalMs) ms")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        Text(record.text).font(.system(size: 13)).lineLimit(1)
                    }
                    Spacer()
                    Button { Clipboard.shared.copy(record.text) } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.borderless)
                        .help("Copy")
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
            }
        }
        .card()
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            content()
        }
    }

    private var statusText: String {
        switch app.parakeetState {
        case .notLoaded: "Ready · \(app.store.tracks.count) tracks"
        case .loading: "Loading Parakeet v3…"
        case .ready: "Ready · \(app.store.tracks.count) tracks · Parakeet loaded"
        case .failed(let error): "Parakeet failed: \(error)"
        }
    }

    private var statusColor: Color {
        switch app.parakeetState {
        case .loading: .orange
        case .failed: .red
        default: .green
        }
    }

    private func openEditor() {
        openWindow(id: "tracks")
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct TrackRow: View {
    let track: Track

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Circle().fill(Color(hex: track.colorHex)).frame(width: 8, height: 8)
                Text(track.name).font(.system(size: 14, weight: .semibold))
                Spacer()
                ForEach(track.triggers) { trigger in
                    HStack(spacing: 4) {
                        Text(trigger.combo.display)
                        Text(trigger.mode == .hold ? "hold" : "toggle").foregroundStyle(.secondary)
                    }
                    .font(.system(size: 11))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.07)))
                }
            }
            HStack(spacing: 4) {
                ForEach(Array(track.steps.enumerated()), id: \.element.id) { index, step in
                    if index > 0 { Text("›").font(.system(size: 11)).foregroundStyle(.tertiary) }
                    StepChip(kind: step.kind)
                }
            }
            .padding(.leading, 16)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

struct StepChip: View {
    let kind: StepKind

    var body: some View {
        Text(kind.chip)
            .font(.system(size: 11))
            .lineLimit(1)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(kind.tint.opacity(0.16)))
            .foregroundStyle(kind.tint)
    }
}

extension StepKind {
    var tint: Color {
        switch category {
        case "Input": .secondary
        case "Output": .green
        default: .blue
        }
    }
}

extension View {
    func card() -> some View {
        background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08)))
    }
}
