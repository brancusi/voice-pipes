import AppKit
import SwiftUI

enum MainSection: Hashable {
    case track(Track.ID)
    case activity
    case vocabulary
    case setup
}

/// The full Voice Pipes window: build tracks, look back at runs, and set up permissions and connections.
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
        .vpWindow()
        .background(WindowBehavior())
        // A menu bar app has no Dock icon and isn't in ⌘Tab, so its window would be unreachable once you click
        // away. While this window is open the app acts like a regular app; when it closes, menu-bar-only again.
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
        .onDisappear {
            NSApp.setActivationPolicy(.accessory)
        }
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
                    HStack(spacing: 8) {
                        Rectangle().fill(Color(hex: track.colorHex)).frame(width: 7, height: 7)
                        Text(track.name)
                        Spacer()
                        if let combo = track.triggers.first?.combo { Keycap(text: combo.display) }
                    }
                    .opacity(track.enabled ? 1 : 0.5)
                    .tag(MainSection.track(track.id))
                }
                .onMove { app.store.tracks.move(fromOffsets: $0, toOffset: $1) }
                Button { newTrack() } label: { Label("New track", systemImage: "plus") }
                    .buttonStyle(.borderless)
            }
            Section("Voice Pipes") {
                Label("History", systemImage: "clock.arrow.circlepath").tag(MainSection.activity)
                Label("Vocabulary", systemImage: "character.book.closed").tag(MainSection.vocabulary)
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
        .scrollContentBackground(.hidden)
        .background(Palette.bg000)
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
            HistoryView(app: app).navigationTitle("History").background(Palette.bg100)
        case .vocabulary:
            VocabularyView(parakeet: app.parakeet).navigationTitle("Vocabulary").background(Palette.bg100)
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

/// Every run's text, kept on disk: search it, copy any of it back, see how long each step took.
private struct HistoryView: View {
    let app: AppState
    @State private var query = ""
    @State private var copied: RunRecord.ID?
    @State private var confirmingClear = false

    private var records: [RunRecord] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return app.history }
        return app.history.filter {
            $0.text.localizedCaseInsensitiveContains(q) || ($0.heard?.localizedCaseInsensitiveContains(q) ?? false)
                || $0.trackName.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        if app.history.isEmpty {
            ContentUnavailableView("No runs yet", systemImage: "waveform",
                                   description: Text("Everything your tracks produce is kept here, so you can copy it again."))
        } else {
            List(records) { record in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(record.trackName).font(VPFont.bodyStrong)
                        Text("· \(record.date.formatted(date: .abbreviated, time: .shortened)) · \(record.totalMs) ms")
                            .font(VPFont.caption).foregroundStyle(Palette.fgMuted)
                        if let failure = record.failure {
                            Text("· " + failure).font(VPFont.caption).foregroundStyle(Palette.orange).lineLimit(1)
                        }
                        Spacer()
                        Button(copied == record.id ? "Copied ✓" : "Copy") {
                            Clipboard.shared.copy(record.text)
                            copied = record.id
                        }
                        .buttonStyle(copied == record.id ? VPButtonStyle(kind: .primary) : VPButtonStyle(kind: .secondary))
                    }
                    if let heard = record.heard {
                        Text("› " + heard).foregroundStyle(Palette.fgMuted).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(record.text).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        ForEach(Array(record.steps.enumerated()), id: \.offset) { _, step in
                            Text("\(step.title) \(step.ms) ms").font(VPFont.caption).foregroundStyle(Palette.fgMuted)
                        }
                    }
                }
                .padding(.vertical, 6)
                .listRowBackground(Palette.bg200)
            }
            .scrollContentBackground(.hidden)
            .searchable(text: $query, prompt: "Search everything you've said")
            .toolbar {
                ToolbarItem {
                    Button("Clear history…") { confirmingClear = true }
                }
            }
            .confirmationDialog("Clear all \(app.history.count) runs from History?", isPresented: $confirmingClear) {
                Button("Clear history", role: .destructive) { app.historyStore.clear() }
            } message: {
                Text("This can't be undone.")
            }
        }
    }
}

/// Permissions, connections, models and updates in one place.
private struct SetupView: View {
    let app: AppState
    @EnvironmentObject var updates: Updates
    @State private var key = ""
    @State private var jevKey = ""
    private var catalog: OpenRouterCatalog { .shared }

    var body: some View {
        Form {
            Group {
            Section {
                ForEach(app.checks) { check in
                    HStack(alignment: .top, spacing: 10) {
                        Text(Self.code(check.level)).font(VPFont.label).tracking(0.9)
                        .foregroundStyle(MenuView.color(check.level)).frame(width: 40, alignment: .leading)
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

            Section {
                LabeledContent("Jev API key") {
                    HStack {
                        SecureField(app.hasJevKey ? "Saved in Keychain — paste to replace" : "TypeSafe key", text: $jevKey)
                            .textFieldStyle(.roundedBorder)
                        Button("Save") { app.setJevKey(jevKey); jevKey = "" }.disabled(jevKey.isEmpty)
                    }
                }
            } header: {
                Text("TypeSafe (Jev)")
            } footer: {
                Text("Used by Route steps (Jev picks the model for each request) and when training vocabulary (Jev judges which mishearings are safe to replace everywhere).")
                    .font(.caption).foregroundStyle(.secondary)
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
            .listRowBackground(Palette.bg200)
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Palette.bg100)
    }

    /// Check levels as log codes, so status never depends on colour alone.
    static func code(_ level: Check.Level) -> String {
        switch level {
        case .ok: "OK"
        case .info: "INFO"
        case .warning: "WARN"
        case .problem: "FAIL"
        }
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

/// The shared word list used by Fix words steps (and given to LLM steps as a glossary).
/// A plain table rather than a Form: Form shows a text field's title as a label beside it.
private struct VocabularyView: View {
    let parakeet: ParakeetService
    @Bindable private var store = VocabularyStore.shared
    @State private var training: VocabularyEntry.ID?
    @State private var sample = "i use cloud code and open router every day."

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Words transcription keeps getting wrong. **Write** is the spelling you want; **Heard as** lists what comes out instead, separated by commas. Replacement is mechanical and instant: whole words only, any capitalization. Spellings with capitals are always written exactly; all-lowercase ones get a capital at the start of a sentence unless **Always exact** is on.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                GroupBox {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow {
                            Text("Write")
                            Text("Heard as")
                            Text("Always exact").gridColumnAlignment(.center)
                            Text("")
                            Text("")
                        }
                        .font(.caption).foregroundStyle(.secondary)
                        ForEach($store.entries) { $entry in
                            GridRow {
                                TextField("", text: $entry.write, prompt: Text("Spelling"))
                                    .labelsHidden()
                                    .multilineTextAlignment(.leading)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(minWidth: 180, maxWidth: 260)
                                TextField("", text: heardAs($entry), prompt: Text("what comes out instead, comma-separated"))
                                    .labelsHidden()
                                    .multilineTextAlignment(.leading)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(minWidth: 260, maxWidth: .infinity)
                                Toggle("", isOn: $entry.alwaysExact)
                                    .labelsHidden()
                                    .toggleStyle(.switch)
                                    .controlSize(.small)
                                    .gridColumnAlignment(.center)
                                Button("Train…") { training = entry.id }
                                    .controlSize(.small)
                                    .disabled(entry.write.trimmingCharacters(in: .whitespaces).isEmpty)
                                    .help("Say it a few times and collect the ways transcription gets it wrong")
                                Button { store.entries.removeAll { $0.id == entry.id } } label: { Image(systemName: "minus.circle") }
                                    .buttonStyle(.borderless)
                                    .help("Remove")
                            }
                        }
                    }
                    .padding(8)
                    HStack {
                        Button { store.entries.append(VocabularyEntry(write: "", heardAs: [])) } label: {
                            Label("Add word", systemImage: "plus")
                        }
                        .buttonStyle(.borderless)
                        Spacer()
                    }
                    .padding([.horizontal, .bottom], 8)
                } label: {
                    Text("Words").font(.headline)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("", text: $sample, prompt: Text("Type or paste a sentence"), axis: .vertical)
                            .labelsHidden()
                            .multilineTextAlignment(.leading)
                            .textFieldStyle(.roundedBorder)
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("Result").font(.caption).foregroundStyle(.secondary)
                            Text(FixWords.apply(sample, entries: store.entries))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(8)
                } label: {
                    Text("Try it").font(.headline)
                }
            }
            .padding(20)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .sheet(isPresented: Binding { training != nil } set: { if !$0 { training = nil } }) {
            if let index = store.entries.firstIndex(where: { $0.id == training }) {
                TrainWordSheet(parakeet: parakeet, entry: $store.entries[index])
            }
        }
    }

    /// Edits the comma-separated list without reformatting it while you type (a trailing comma or space stays).
    private func heardAs(_ entry: Binding<VocabularyEntry>) -> Binding<String> {
        Binding {
            entry.wrappedValue.heardAsText ?? entry.wrappedValue.heardAs.joined(separator: ", ")
        } set: { text in
            entry.wrappedValue.heardAsText = text
            entry.wrappedValue.heardAs = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
    }
}

/// Keeps the main window on screen when another app is in front (it must never hide on deactivate).
private struct WindowBehavior: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.hidesOnDeactivate = false
            view.window?.isReleasedWhenClosed = false
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
