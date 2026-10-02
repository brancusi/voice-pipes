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
    /// Narrowest the detail pages lay out properly. Pages squeeze down to this; below it (a narrow tile with the
    /// sidebar showing) they scroll sideways instead of being clipped on both edges.
    static let detailMinWidth: CGFloat = 380

    var body: some View {
        NavigationSplitView {
            sidebar.navigationSplitViewColumnWidth(min: 220, ideal: 240)
        } detail: {
            detail.scrollsSidewaysBelow(Self.detailMinWidth)
        }
        .frame(minWidth: 420, minHeight: 320)
        // Small minimums on purpose: tiling window managers (yabai, Stage Manager, split screen) size the window
        // to its tile, and a window that refuses to shrink spills into the neighbouring one.
        .vpWindow()
        .background(WindowBehavior())
        // A menu bar app has no Dock icon and isn't in ⌘Tab, so its window would be unreachable once you click
        // away. While this window is open the app acts like a regular app; when it closes, menu-bar-only again.
        .onAppear { WindowBehavior.opened() }
        .onDisappear { WindowBehavior.closed() }
        .onAppear {
            if app.mainSection == nil { app.mainSection = app.store.tracks.first.map { .track($0.id) } ?? .setup }
            app.refreshChecks()
            OpenRouterCatalog.shared.refreshIfStale()
        }
    }

    #if SNAPSHOTS
    /// Harness only: the sidebar and the page side by side (a split view doesn't render offscreen).
    var snapshotBody: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 230)
            Rectangle().fill(Palette.line).frame(width: 1)
            detail.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .vpWindow()
    }
    #endif

    private var sidebar: some View {
        List(selection: $app.mainSection) {
            Section {
                ForEach(app.store.tracks) { track in
                    HStack(spacing: 8) {
                        Rectangle().fill(Palette.track(track.colorHex)).frame(width: 7, height: 7)
                        Text(track.name).lineLimit(1)
                        Spacer(minLength: 4)
                        if let combo = track.triggers.first?.combo { Keycap(text: combo.display) }
                    }
                    .opacity(track.enabled ? 1 : 0.4)
                    .tag(MainSection.track(track.id))
                }
                .onMove { app.store.tracks.move(fromOffsets: $0, toOffset: $1) }
                Button { newTrack() } label: {
                    Text("+ New track").foregroundStyle(Palette.purple)
                }
                .buttonStyle(.plain)
            } header: {
                SectionLabel("Tracks")
            }
            Section {
                Text("History").tag(MainSection.activity)
                Text("Vocabulary").tag(MainSection.vocabulary)
                HStack {
                    Text("Setup")
                    Spacer()
                    if app.worstCheck >= .warning { StatusCode(level: app.worstCheck, width: nil) }
                }
                .tag(MainSection.setup)
            } header: {
                Hairline().padding(.vertical, 4)
            }
        }
        .listStyle(.sidebar)
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
            VocabularyView(parakeet: app.parakeet).scrollsSidewaysBelow(520).navigationTitle("Vocabulary").background(Palette.bg100)
        case .setup, nil:
            SetupView(app: app).navigationTitle("Setup")
        }
    }

    private func newTrack() {
        let track = Track(name: "New track", colorHex: Palette.trackSwatches[app.store.tracks.count % Palette.trackSwatches.count].hex,
                          triggers: [],
                          steps: [Step(kind: .microphone), Step(kind: .parakeet(chunkOnPauseMs: 500, mode: .onRelease)),
                                  Step(kind: .paste(restoreClipboard: true))])
        app.store.tracks.append(track)
        app.mainSection = .track(track.id)
    }
}

/// Every run's text, kept on disk: search it, filter by track, copy any of it back, see each step's time.
private struct HistoryView: View {
    let app: AppState
    @State private var query = ""
    @State private var trackFilter: String?
    @State private var copied: RunRecord.ID?
    @State private var confirmingClear = false

    private var records: [RunRecord] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return app.history.filter { record in
            (trackFilter == nil || record.trackName == trackFilter)
                && (q.isEmpty || record.text.localizedCaseInsensitiveContains(q)
                    || (record.heard?.localizedCaseInsensitiveContains(q) ?? false)
                    || record.trackName.localizedCaseInsensitiveContains(q))
        }
    }

    /// Track names that appear in History, in the sidebar's order, then any others (renamed or deleted tracks).
    private var trackNames: [String] {
        let present = Set(app.history.map(\.trackName))
        let ordered = app.store.tracks.map(\.name).filter(present.contains)
        return ordered + present.subtracting(ordered).sorted()
    }

    private var days: [(String, [RunRecord])] {
        let calendar = Calendar.current
        var groups: [(String, [RunRecord])] = []
        for record in records {
            let label = calendar.isDateInToday(record.date) ? "Today"
                : calendar.isDateInYesterday(record.date) ? "Yesterday"
                : record.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
            if groups.last?.0 == label { groups[groups.count - 1].1.append(record) } else { groups.append((label, [record])) }
        }
        return groups
    }

    var body: some View {
        Group {
            if app.history.isEmpty {
                EmptyHistory(hotkey: app.store.tracks.first { $0.enabled && !$0.triggers.isEmpty }?.triggers.first?.combo.display)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        filters
                        if records.isEmpty {
                            Text("Nothing matches. Try fewer words, or All.").font(VPFont.caption).foregroundStyle(Palette.fgMuted)
                        }
                        ForEach(days, id: \.0) { day in
                            VStack(alignment: .leading, spacing: 6) {
                                SectionLabel(day.0)
                                Card {
                                    ForEach(Array(day.1.enumerated()), id: \.element.id) { index, record in
                                        if index > 0 { Hairline() }
                                        row(record)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 28).padding(.vertical, 24)
                    .frame(maxWidth: 900, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .toolbar {
                    ToolbarItem {
                        Button("Clear history…") { confirmingClear = true }
                    }
                }
            }
        }
        .background(Palette.bg100)
        .confirmationDialog("Clear all \(app.history.count) runs from History?", isPresented: $confirmingClear) {
            Button("Clear history", role: .destructive) { app.historyStore.clear() }
        } message: {
            Text("This can't be undone.")
        }
    }

    private var filters: some View {
        HStack(spacing: 8) {
            VPTextField("Search everything you've said", text: $query).frame(maxWidth: 300)
            VPChip(title: "All", selected: trackFilter == nil) { trackFilter = nil }
            ForEach(trackNames.prefix(5), id: \.self) { name in
                VPChip(title: name, selected: trackFilter == name) { trackFilter = trackFilter == name ? nil : name }
            }
            Spacer(minLength: 8)
            Text("\(app.history.count.formatted()) runs · on this Mac").font(VPFont.caption).foregroundStyle(Palette.fgMuted)
                .lineLimit(1).fixedSize()
        }
    }

    private func row(_ record: RunRecord) -> some View {
        let failed = record.failure != nil
        let color = failed ? Palette.orange
            : (record.colorHex ?? app.store.tracks.first { $0.name == record.trackName }?.colorHex).map(Palette.track) ?? Palette.fgMuted
        return HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Rectangle().fill(color).frame(width: 7, height: 7)
                    (Text("\(record.trackName) · \(record.date.formatted(date: .omitted, time: .shortened)) · \(record.totalMs.msLabel)")
                        + (record.failure.map { Text(" · " + $0).foregroundColor(Palette.orange) } ?? Text("")))
                        .font(VPFont.caption).foregroundStyle(Palette.fgMuted).lineLimit(1)
                }
                if let heard = record.heard {
                    Text("› " + heard).foregroundStyle(Palette.fgMuted).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(record.text).lineSpacing(3).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                if !record.steps.isEmpty { StepChain(steps: record.steps) }
            }
            Spacer(minLength: 0)
            Button(copied == record.id ? "Copied ✓" : "Copy") {
                Clipboard.shared.copy(record.text)
                copied = record.id
            }
            .buttonStyle(copied == record.id ? VPButtonStyle(kind: .primary) : VPButtonStyle(kind: .secondary))
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(failed ? Palette.bg300 : .clear)
    }
}

/// A run's steps in order, `›` between them, each in its category's colour with its time.
private struct StepChain: View {
    let steps: [RunRecord.StepTiming]

    var body: some View {
        steps.enumerated().reduce(Text("")) { text, item in
            let (index, step) = item
            let piece = Text("\(step.title) \(step.ms.msLabel)").foregroundColor(Self.color(step.category ?? Self.guessCategory(step.title)))
            return index == 0 ? piece : text + Text("  ›  ").foregroundColor(Palette.comment) + piece
        }
        .font(VPFont.caption)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Runs saved before 1.4.0 have no category; infer it from the step's title.
    static func guessCategory(_ title: String) -> String? {
        let t = title.lowercased()
        if ["parakeet", "transcri", "whisper", "mai-", "voxtral"].contains(where: { t.contains($0) }) { return "Transcribe" }
        if ["paste", "copy", "speak", "show in hud", "pocket tts", "supertonic"].contains(where: { t.hasPrefix($0) }) { return "Output" }
        if t == "text" || t.hasPrefix("microphone") { return "Input" }
        return "Transform"
    }

    static func color(_ category: String?) -> Color {
        switch category {
        case "Transcribe": Palette.cyan
        case "Transform": Palette.purple
        case "Output": Palette.green
        default: Palette.fgMuted
        }
    }
}

/// First launch: the Wrangler busking, a flavour headline, then plain instructions.
private struct EmptyHistory: View {
    let hotkey: String?

    var body: some View {
        VStack(spacing: 18) {
            Wrangler(pose: .busk, scale: 6)
            PixelHeadline("quiet on the range")
            (Text("No runs yet. ") + (hotkey.map { Text("Hold ") + Text($0).foregroundColor(Palette.fg) + Text(" and say something; ") }
                ?? Text("Run a track and say something; ")) + Text("every run lands here so you can copy it again."))
                .font(VPFont.body).lineSpacing(4).foregroundStyle(Palette.fgMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 330)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    .font(VPFont.caption).lineSpacing(3).foregroundStyle(Palette.fgMuted)
                    .fixedSize(horizontal: false, vertical: true)

                VPSection("Words") {
                    Card {
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                            GridRow {
                                Text("Write")
                                Text("Heard as")
                                Text("Always exact").gridColumnAlignment(.center)
                                Text("")
                                Text("")
                            }
                            .font(VPFont.caption).foregroundStyle(Palette.fgMuted)
                            ForEach($store.entries) { $entry in
                                GridRow {
                                    VPTextField("Spelling", text: $entry.write)
                                        .frame(minWidth: 120, maxWidth: 260)
                                    VPTextField("what comes out instead, comma-separated", text: heardAs($entry))
                                        .frame(minWidth: 160, maxWidth: .infinity)
                                    Toggle("Always exact", isOn: $entry.alwaysExact)
                                        .labelsHidden()
                                        .toggleStyle(.switch)
                                        .controlSize(.small)
                                        .gridColumnAlignment(.center)
                                    Button("Train…") { training = entry.id }
                                        .buttonStyle(.vpSecondary)
                                        .disabled(entry.write.trimmingCharacters(in: .whitespaces).isEmpty)
                                        .help("Say it a few times and collect the ways transcription gets it wrong")
                                    Button { store.entries.removeAll { $0.id == entry.id } } label: { Image(systemName: "trash") }
                                        .buttonStyle(.vpIcon)
                                        .help("Remove")
                                }
                            }
                        }
                        .padding(12)
                        Hairline()
                        Button("+ Add word") { store.entries.append(VocabularyEntry(write: "", heardAs: [])) }
                            .buttonStyle(.vpGhost)
                            .padding(6)
                    }
                }

                VPSection("Try it") {
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            VPTextField("Type or paste a sentence", text: $sample, axis: .vertical)
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("Result").font(VPFont.caption).foregroundStyle(Palette.fgMuted)
                                Text(FixWords.apply(sample, entries: store.entries))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(12)
                    }
                }
            }
            .padding(.horizontal, 32).padding(.vertical, 24)
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

extension View {
    /// Lays the view out at least `minWidth` wide; when the space is narrower it scrolls left and right
    /// (still full height, so the page's own vertical scrolling keeps working) rather than being centred and clipped.
    func scrollsSidewaysBelow(_ minWidth: CGFloat) -> some View {
        // One view tree at every width (no if/else), so resizing past the threshold doesn't reset the page's state.
        GeometryReader { geo in
            ScrollView(.horizontal) {
                self.frame(width: max(geo.size.width, minWidth), height: geo.size.height)
            }
            .scrollDisabled(geo.size.width >= minWidth)
        }
    }
}

/// Keeps a window on screen when another app is in front (it must never hide on deactivate), and makes the app a
/// regular Dock app while any of its windows is open: a menu bar app's window is otherwise unreachable behind others.
struct WindowBehavior: NSViewRepresentable {
    static func opened() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Back to menu-bar-only once the last of the main and About windows has closed.
    static func closed() {
        DispatchQueue.main.async {
            let open = NSApp.windows.contains { window in
                window.isVisible && ["main", "about"].contains { window.identifier?.rawValue.hasPrefix($0) ?? false }
            }
            if !open { NSApp.setActivationPolicy(.accessory) }
        }
    }

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
