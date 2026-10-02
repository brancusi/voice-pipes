import SwiftUI

struct MenuView: View {
    @Bindable var app: AppState
    @EnvironmentObject var updates: Updates
    @Environment(\.openWindow) private var openWindow

    /// The panel is as tall as its content (no scrolling): one compact line per track, three recent runs.
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if let version = updates.available { updateCard(version) }
            section("Tracks") { tracks }
            if app.speaker.state != .idle { section("Now playing") { nowPlaying } }
            if !app.history.isEmpty { historySection }
            if app.worstCheck >= .warning { issuesCard }
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 360)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            updates.poll()
            app.refreshChecks()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("Voice Tools").font(.headline)
                HStack(spacing: 5) {
                    Circle().fill(headline.1).frame(width: 7, height: 7)
                    Text(headline.0).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if app.checking || app.parakeetState == .loading { ProgressView().controlSize(.small) }
        }
    }

    private var headline: (String, Color) {
        switch app.worstCheck {
        case .problem: ("Needs setup", .red)
        case .warning: ("Needs attention", .orange)
        default: (parakeetLine, .green)
        }
    }

    private var parakeetLine: String {
        switch app.parakeetState {
        case .loading: "Loading Parakeet v3…"
        case .ready: "Ready · Parakeet loaded"
        default: "Ready"
        }
    }

    private func updateCard(_ version: String) -> some View {
        HStack {
            Label("Version \(version) is available", systemImage: "arrow.down.circle.fill")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Button("Install…") { updates.check() }.buttonStyle(.borderedProminent).controlSize(.small)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.green.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.08)))
    }

    /// Problems only, in one line; the details and fixes live in the main window's Setup.
    private var issuesCard: some View {
        let issues = app.checks.filter { $0.level >= .warning }
        let worst = issues.map(\.level).max() ?? .warning
        return Button { openMain(.setup) } label: {
            HStack(spacing: 10) {
                Image(systemName: worst == .problem ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(Self.color(worst))
                VStack(alignment: .leading, spacing: 1) {
                    Text(issues.count == 1 ? issues[0].title : "\(issues.count) things need attention").font(.callout)
                    Text(issues.count == 1 ? issues[0].detail : issues.map(\.title).joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                Text("Fix…").font(.callout).foregroundStyle(.tint)
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(RoundedRectangle(cornerRadius: 12).fill(Self.color(worst).opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.08)))
    }

    private var footer: some View {
        HStack {
            Button { openMain(nil) } label: { Label("Open Voice Tools…", systemImage: "macwindow") }
                .help("Tracks, history and setup in a full window")
            Button { app.copyReport() } label: { Image(systemName: "doc.on.clipboard") }
                .help("Copy a report for troubleshooting")
            Button { updates.check() } label: { Image(systemName: "arrow.down.circle") }
                .help(updates.enabled ? "Check for updates (version \(updates.version))" : "Updates are off in this build")
                .disabled(!updates.enabled)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
        }
        .buttonStyle(.borderless)
    }

    static func color(_ level: Check.Level) -> Color {
        switch level {
        case .ok: .green
        case .info: .blue
        case .warning: .orange
        case .problem: .red
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
                Text(app.speaker.state == .paused ? "Paused" : app.speaker.state == .loading ? "Loading" : "Speaking")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(Color.orange.opacity(0.18)))
                Text(app.speaker.sourceLabel).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
            }
            ProgressView(value: app.speaker.progress)
            HStack {
                if app.speaker.state == .loading {
                    ProgressView().controlSize(.small)
                    Text("Preparing voice…").font(.caption).foregroundStyle(.secondary)
                } else {
                    Button(app.speaker.state == .paused ? "Resume" : "Pause") { app.speaker.togglePause() }
                        .buttonStyle(.borderedProminent)
                }
                if app.speaker.canGoBack {
                    Button { app.speaker.back() } label: { Image(systemName: "backward.fill") }.help("Replay this passage")
                }
                Button("Clear") { app.speaker.clear() }
                Spacer()
                Text(app.speaker.voiceLabel).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(12)
        .card()
    }

    /// The last three runs, each one click from the clipboard; the rest are in the window's History.
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("HISTORY").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Button("All \(app.history.count) →") { openMain(.activity) }
                    .buttonStyle(.borderless).font(.system(size: 11))
            }
            .padding(.horizontal, 4)
            recent
        }
    }

    private var recent: some View {
        VStack(spacing: 0) {
            ForEach(Array(app.history.prefix(3).enumerated()), id: \.element.id) { index, record in
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
                .padding(.horizontal, 10).padding(.vertical, 7)
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

    /// Opens the main window, optionally at a section (Setup for problems).
    private func openMain(_ section: MainSection?) {
        if let section { app.mainSection = section }
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct TrackRow: View {
    let track: Track

    /// One line: color, name, hotkeys. The pipeline is in the tooltip and the main window.
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(Color(hex: track.colorHex)).frame(width: 7, height: 7)
            Text(track.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
            Spacer(minLength: 8)
            ForEach(track.triggers) { trigger in
                Text(trigger.combo.display)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.07)))
            }
        }
        .padding(.horizontal, 10).frame(height: 30)
        .contentShape(Rectangle())
        .help(track.steps.map(\.kind.chip).joined(separator: " › ")
              + track.triggers.map { "\n\($0.combo.display): \($0.mode == .hold ? "hold" : "press to start and stop")" }.joined())
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
