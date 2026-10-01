import SwiftUI

struct MenuView: View {
    @Bindable var app: AppState
    @EnvironmentObject var updates: Updates
    @Environment(\.openWindow) private var openWindow
    @State private var contentHeight: CGFloat = 400

    /// A menu bar window taller than the screen gets misplaced by macOS; longer content scrolls instead.
    private var maxHeight: CGFloat { (NSScreen.main?.visibleFrame.height ?? 800) - 40 }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 14) {
                header
                if let version = updates.available { updateCard(version) }
                section("Tracks") { tracks }
                if app.speaker.state != .idle { section("Now playing") { nowPlaying } }
                if !app.history.isEmpty { section("Recent runs") { recent } }
                if app.worstCheck >= .warning { issuesCard }
                Divider()
                footer
            }
            .padding(14)
            .frame(width: 400)
            .background(GeometryReader { g in Color.clear.preference(key: HeightKey.self, value: g.size.height) })
        }
        .frame(width: 400, height: min(contentHeight, maxHeight))
        .onPreferenceChange(HeightKey.self) { contentHeight = $0 }
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
                .help("Tracks, activity and setup in a full window")
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

    /// Opens the main window, optionally at a section (Setup for problems).
    private func openMain(_ section: MainSection?) {
        if let section { app.mainSection = section }
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct HeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 400
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
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
