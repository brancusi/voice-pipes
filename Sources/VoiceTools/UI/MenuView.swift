import SwiftUI

/// The menu bar panel: a quick launcher. One line per track, what's playing, the last three runs.
struct MenuView: View {
    @Bindable var app: AppState
    @EnvironmentObject var updates: Updates
    @Environment(\.openWindow) private var openWindow

    /// The panel is as tall as its content (no scrolling).
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if let version = updates.available { updateCard(version) }
            section("Tracks") { tracks }
            if app.speaker.state != .idle { section("Now playing") { nowPlaying } }
            if !app.history.isEmpty { historySection }
            if app.worstCheck >= .warning { issuesCard }
            Rectangle().fill(Palette.line).frame(height: 1)
            footer
        }
        .padding(14)
        .frame(width: 360)
        .fixedSize(horizontal: false, vertical: true)
        .background(Palette.bg000)
        .vpWindow()
        .onAppear {
            updates.poll()
            app.refreshChecks()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("Voice Pipes").font(VPFont.title)
                HStack(spacing: 6) {
                    Rectangle().fill(headline.1).frame(width: 7, height: 7)
                    Text(headline.0).font(VPFont.caption).foregroundStyle(Palette.fgMuted)
                }
            }
            Spacer()
            if app.checking || app.parakeetState == .loading { ProgressView().controlSize(.small) }
        }
    }

    private var headline: (String, Color) {
        switch app.worstCheck {
        case .problem: ("FAIL · Needs setup", Palette.red)
        case .warning: ("WARN · Needs attention", Palette.orange)
        default: (parakeetLine, Palette.green)
        }
    }

    private var parakeetLine: String {
        switch app.parakeetState {
        case .loading: "PROC · Loading Parakeet v3…"
        case .ready: "OK · Parakeet loaded"
        default: "OK · Ready"
        }
    }

    private func updateCard(_ version: String) -> some View {
        HStack(spacing: 10) {
            Text("NEW").font(VPFont.label).tracking(0.9).foregroundStyle(Palette.green)
            Text("Version \(version) is ready").font(VPFont.body)
            Spacer()
            Button("Install…") { updates.check() }.buttonStyle(.vpPrimary)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 6).fill(Palette.bg200))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.green, lineWidth: 1))
    }

    /// Problems only, in one line; the details and fixes live in the main window's Setup.
    private var issuesCard: some View {
        let issues = app.checks.filter { $0.level >= .warning }
        let worst = issues.map(\.level).max() ?? .warning
        return Button { openMain(.setup) } label: {
            HStack(spacing: 10) {
                Text(worst == .problem ? "FAIL" : "WARN").font(VPFont.label).tracking(0.9)
                    .foregroundStyle(Self.color(worst))
                VStack(alignment: .leading, spacing: 1) {
                    Text(issues.count == 1 ? issues[0].title : "\(issues.count) things need attention").font(VPFont.body)
                    Text(issues.count == 1 ? issues[0].detail : issues.map(\.title).joined(separator: " · "))
                        .font(VPFont.caption).foregroundStyle(Palette.fgMuted).lineLimit(2)
                }
                Spacer()
                Text("Fix…").font(VPFont.bodyStrong).foregroundStyle(Palette.purple)
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .vpCard()
    }

    private var footer: some View {
        HStack(spacing: 4) {
            Button("Open Voice Pipes…") { openMain(nil) }
                .buttonStyle(.vpGhost)
                .help("Tracks, history and setup in a full window")
            Button { app.copyReport() } label: { Image(systemName: "doc.on.clipboard") }
                .buttonStyle(.vpIcon)
                .help("Copy a report for troubleshooting")
            Button { updates.check() } label: { Image(systemName: "arrow.down.circle") }
                .buttonStyle(.vpIcon)
                .help(updates.enabled ? "Check for updates (version \(updates.version))" : "Updates are off in this build")
                .disabled(!updates.enabled)
            Spacer()
            Button { NSApp.terminate(nil) } label: { Text("Quit").foregroundStyle(Palette.fgMuted) }
                .buttonStyle(.vpGhost)
        }
    }

    static func color(_ level: Check.Level) -> Color {
        switch level {
        case .ok: Palette.green
        case .info: Palette.cyan
        case .warning: Palette.orange
        case .problem: Palette.red
        }
    }

    private var tracks: some View {
        VStack(spacing: 0) {
            ForEach(Array(app.store.tracks.enumerated()), id: \.element.id) { index, track in
                if index > 0 { Rectangle().fill(Palette.line).frame(height: 1) }
                Button { app.start(track) } label: {
                    TrackRow(track: track, playing: app.run?.trackID == track.id)
                }
                .buttonStyle(.plain)
                .opacity(track.enabled ? 1 : 0.4)
            }
        }
        .vpCard()
    }

    private var nowPlaying: some View {
        let speaker = app.speaker
        let (code, color): (String, Color) = switch speaker.state {
        case .paused: ("PAUSED", Palette.fgMuted)
        case .loading: ("VOICE", Palette.purple)
        default: ("READ", Palette.purple)
        }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Rectangle().fill(color).frame(width: 7, height: 7)
                Text(code).font(VPFont.label).tracking(0.9)
                Text(speaker.state == .loading ? "···" : "\(Int(speaker.progress * 100))%")
                    .font(VPFont.caption).foregroundStyle(Palette.fgMuted)
                Spacer()
                Text(speaker.voiceLabel).font(VPFont.caption).foregroundStyle(Palette.fgMuted).lineLimit(1)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(Palette.bg300)
                    RoundedRectangle(cornerRadius: 2).fill(Palette.purple).frame(width: geo.size.width * speaker.progress)
                }
            }
            .frame(height: 4)
            if let info = app.run?.modelInfo {
                Text(info).font(VPFont.caption).foregroundStyle(Palette.fgMuted).lineLimit(1).truncationMode(.middle)
            }
            HStack(spacing: 6) {
                if speaker.state == .loading {
                    ProgressView().controlSize(.small)
                    Text("Preparing voice…").font(VPFont.caption).foregroundStyle(Palette.fgMuted)
                } else {
                    Button(speaker.state == .paused ? "Resume" : "Pause") { speaker.togglePause() }
                        .buttonStyle(.vpPrimary)
                }
                if speaker.canGoBack {
                    Button { speaker.back() } label: { Image(systemName: "backward.end.fill") }
                        .buttonStyle(.vpIcon).help("Replay this passage")
                }
                Button("Stop") { speaker.clear() }.buttonStyle(.vpSecondary)
            }
        }
        .padding(12)
        .vpCard()
    }

    /// The last three runs, each one click from the clipboard; the rest are in the window's History.
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionLabel("History")
                Spacer()
                Button("All \(app.history.count) →") { openMain(.activity) }
                    .buttonStyle(.plain).font(VPFont.caption).foregroundStyle(Palette.purple)
            }
            .padding(.horizontal, 4)
            VStack(spacing: 0) {
                ForEach(Array(app.history.prefix(3).enumerated()), id: \.element.id) { index, record in
                    if index > 0 { Rectangle().fill(Palette.line).frame(height: 1) }
                    HistoryRow(record: record)
                }
            }
            .vpCard()
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(title).padding(.horizontal, 4)
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
    let playing: Bool
    @State private var hovering = false

    /// One line: colour, name, hotkeys. The pipeline is in the tooltip and the main window.
    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(Color(hex: track.colorHex)).frame(width: 7, height: 7)
            Text(track.name).font(VPFont.body).lineLimit(1)
            Spacer(minLength: 8)
            if playing { Text("▶").font(VPFont.caption).foregroundStyle(Palette.purple) }
            ForEach(track.triggers) { trigger in Keycap(text: trigger.combo.display) }
        }
        .padding(.horizontal, 12).frame(height: 30)
        .background(hovering || playing ? Palette.bg300 : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help(track.steps.map(\.kind.chip).joined(separator: " › ")
              + track.triggers.map { "\n\($0.combo.display): \($0.mode == .hold ? "hold" : "press to start and stop")" }.joined())
    }
}

private struct HistoryRow: View {
    let record: RunRecord
    @State private var copied = false

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 0) {
                    Text("\(record.trackName) · \(record.date.formatted(.relative(presentation: .named))) · \(record.totalMs) ms")
                        .foregroundStyle(Palette.fgMuted)
                    if record.failure != nil { Text(" · failed").foregroundStyle(Palette.orange) }
                }
                .font(VPFont.caption).lineLimit(1)
                Text(record.text).font(VPFont.body).lineLimit(1)
            }
            Spacer()
            Button {
                Clipboard.shared.copy(record.text)
                copied = true
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc").foregroundStyle(copied ? Palette.green : Palette.fgMuted)
            }
            .buttonStyle(.vpIcon)
            .help(copied ? "Copied" : "Copy")
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
    }
}
