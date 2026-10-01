import SwiftUI

enum MainSection: Hashable {
    case track(Track.ID)
    case activity
    case setup
}

/// The full Voice Tools window: build tracks, look back at runs, and set up permissions and connections.
/// The menu bar panel stays a quick launcher.
struct MainWindowView: View {
    @Bindable var app: AppState

    var body: some View {
        NavigationSplitView {
            sidebar.navigationSplitViewColumnWidth(min: 220, ideal: 240)
        } detail: {
            detail
        }
        .frame(minWidth: 900, minHeight: 640)
        .onAppear {
            if app.mainSection == nil { app.mainSection = app.store.tracks.first.map { .track($0.id) } ?? .setup }
            app.refreshChecks()
            OpenRouterCatalog.shared.refreshIfStale()
        }
    }

    private var sidebar: some View {
        List(selection: $app.mainSection) {
            Section("Tracks") {
                ForEach(app.store.tracks) { track in
                    HStack {
                        Circle().fill(Color(hex: track.colorHex)).frame(width: 8, height: 8)
                        Text(track.name)
                        Spacer()
                        Text(track.triggers.first?.combo.display ?? "").font(.caption).foregroundStyle(.secondary)
                    }
                    .opacity(track.enabled ? 1 : 0.5)
                    .tag(MainSection.track(track.id))
                }
                .onMove { app.store.tracks.move(fromOffsets: $0, toOffset: $1) }
                Button { newTrack() } label: { Label("New track", systemImage: "plus") }
                    .buttonStyle(.borderless)
            }
            Section("Voice Tools") {
                Label("Activity", systemImage: "clock.arrow.circlepath").tag(MainSection.activity)
                HStack {
                    Label("Setup", systemImage: "checklist")
                    Spacer()
                    if app.worstCheck >= .warning {
                        Image(systemName: app.worstCheck == .problem ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(app.worstCheck == .problem ? .red : .orange)
                    }
                }
                .tag(MainSection.setup)
            }
        }
    }

    @ViewBuilder private var detail: some View {
        switch app.mainSection {
        case .track(let id):
            if let index = app.store.tracks.firstIndex(where: { $0.id == id }) {
                TrackDetailView(app: app, track: Bindable(app.store).tracks[index]) {
                    app.store.tracks.remove(at: index)
                    app.mainSection = app.store.tracks.first.map { .track($0.id) } ?? .setup
                }
                .id(id)
                .navigationTitle(app.store.tracks[index].name)
            } else {
                Text("Select a track").foregroundStyle(.secondary)
            }
        case .activity:
            ActivityView(app: app).navigationTitle("Activity")
        case .setup, nil:
            SetupView(app: app).navigationTitle("Setup")
        }
    }

    private func newTrack() {
        let track = Track(name: "New track", colorHex: "#1F9D55", triggers: [],
                          steps: [Step(kind: .microphone), Step(kind: .parakeet(chunkOnPauseMs: 500, mode: .onRelease)),
                                  Step(kind: .paste(restoreClipboard: true))])
        app.store.tracks.append(track)
        app.mainSection = .track(track.id)
    }
}

/// Every run this session, with what came out and how long each step took.
private struct ActivityView: View {
    let app: AppState

    var body: some View {
        if app.history.isEmpty {
            ContentUnavailableView("No runs yet", systemImage: "waveform",
                                   description: Text("Trigger a track with its hotkey or from the menu bar."))
        } else {
            List(app.history) { record in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(record.trackName).font(.headline)
                        Text(record.date.formatted(date: .omitted, time: .shortened)).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(record.totalMs) ms").monospacedDigit().foregroundStyle(.secondary)
                        Button { Clipboard.shared.copy(record.text) } label: { Image(systemName: "doc.on.doc") }
                            .buttonStyle(.borderless).help("Copy")
                    }
                    Text(record.text).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        ForEach(Array(record.steps.enumerated()), id: \.offset) { _, step in
                            Text("\(step.title) \(step.ms) ms").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }
}

/// Permissions, connections, models and updates in one place.
private struct SetupView: View {
    let app: AppState
    @EnvironmentObject var updates: Updates
    @State private var key = ""
    private var catalog: OpenRouterCatalog { .shared }

    var body: some View {
        Form {
            Section {
                ForEach(app.checks) { check in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: check.symbol).foregroundStyle(MenuView.color(check.level)).frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(check.title)
                            Text(check.detail).font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        if let fix = check.fix, fix != .editTracks {
                            Button("Fix…") { app.fix(fix) }
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Checks")
                    Spacer()
                    if app.checking { ProgressView().controlSize(.small) }
                    Button("Check again") { app.refreshChecks() }.controlSize(.small)
                    Button("Copy report") { app.copyReport() }.controlSize(.small)
                }
            }

            Section("OpenRouter") {
                LabeledContent("API key") {
                    HStack {
                        SecureField(app.hasOpenRouterKey ? "Saved in Keychain — paste to replace" : "sk-or-…", text: $key)
                            .textFieldStyle(.roundedBorder)
                        Button("Save") { app.setOpenRouterKey(key); key = "" }.disabled(key.isEmpty)
                    }
                }
                LabeledContent("Models") {
                    HStack {
                        if catalog.loading { ProgressView().controlSize(.small) }
                        Text(catalogLine).foregroundStyle(.secondary)
                        Button("Reload") { catalog.refresh() }.controlSize(.small)
                    }
                }
                if let error = catalog.error { Text(error).font(.caption).foregroundStyle(.orange) }
            }

            Section("On this Mac") {
                LabeledContent("Parakeet v3", value: parakeetLabel)
                ForEach(LocalVoiceEngine.allCases) { engine in
                    LabeledContent(engine.label) {
                        HStack {
                            let state = app.localVoiceStates[engine] ?? .notLoaded
                            if state == .loading { ProgressView().controlSize(.small) }
                            Text(Self.label(state)).foregroundStyle(.secondary)
                            if state == .notLoaded || { if case .failed = state { true } else { false } }() {
                                Button("Load now") { Task { try? await LocalVoices.shared.prepare(engine) } }.controlSize(.small)
                            }
                        }
                    }
                }
            }

            Section("Updates") {
                LabeledContent("Version", value: updates.version)
                HStack {
                    Text(updates.enabled ? "Checks for new versions every few minutes." : "Updates are off in this build.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Check now") { updates.check() }.disabled(!updates.enabled)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var catalogLine: String {
        let speech = catalog.models(for: .speech).count, stt = catalog.models(for: .transcription).count
        let text = catalog.models(for: .text).count
        guard !catalog.models.isEmpty else { return "Not loaded" }
        let when = catalog.updated.map { " · \($0.formatted(.relative(presentation: .named)))" } ?? ""
        return "\(text) language · \(stt) transcription · \(speech) speech\(when)"
    }

    static func label(_ state: LocalVoices.State) -> String {
        switch state {
        case .notLoaded: "Downloads and loads on first use"
        case .loading: "Downloading / loading…"
        case .ready: "Loaded"
        case .failed(let error): "Failed: \(error)"
        }
    }

    private var parakeetLabel: String {
        switch app.parakeetState {
        case .notLoaded: "Loads on first use"
        case .loading: "Loading…"
        case .ready: "Loaded"
        case .failed(let error): "Failed: \(error)"
        }
    }
}
