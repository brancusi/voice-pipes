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
            sidebar.navigationSplitViewColumnWidth(min: 250, ideal: 250)
        } detail: {
            detail.scrollsSidewaysBelow(Self.detailMinWidth)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { VersionFooter() }
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
            sidebar.frame(width: 250)
            Rectangle().fill(Palette.line).frame(width: 1)
            detail.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .vpWindow()
    }

    /// Harness only: the page alone (a narrow tile with the sidebar hidden).
    var snapshotDetail: some View { detail.vpWindow() }
    #endif

    private var sidebar: some View {
        // No List selection: the system draws it as a neutral grey pill; ours is the palette's bg300.
        List {
            Section {
                ForEach(app.store.tracks) { track in
                    sidebarItem(.track(track.id)) {
                        HStack(spacing: 8) {
                            Rectangle().fill(Palette.track(track.colorHex)).frame(width: 7, height: 7)
                            Text(track.name).lineLimit(1).help(track.name)
                            Spacer(minLength: 4)
                            if let combo = track.triggers.first?.combo { Keycap(text: combo.display) }
                        }
                        .opacity(track.enabled ? 1 : 0.4)
                    }
                }
                .onMove { app.store.tracks.move(fromOffsets: $0, toOffset: $1) }
                Button { newTrack() } label: {
                    Text("+ New track").foregroundStyle(Palette.purple)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .listRowBackground(Color.clear)
            } header: {
                SectionLabel("Tracks")
            }
            Section {
                sidebarItem(.activity) { Text("History") }
                sidebarItem(.vocabulary) { Text("Vocabulary") }
                sidebarItem(.setup) {
                    HStack {
                        Text("Setup")
                        Spacer()
                        if app.worstCheck >= .warning { StatusCode(level: app.worstCheck, width: nil) }
                    }
                }
            } header: {
                Hairline().padding(.vertical, 4)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Palette.bg000)
        // ↑↓ move through the sidebar (the system list did this; ours draws its own selection).
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.downArrow) { moveSection(1); return .handled }
        .onKeyPress(.upArrow) { moveSection(-1); return .handled }
    }

    private var sidebarOrder: [MainSection] {
        app.store.tracks.map { MainSection.track($0.id) } + [.activity, .vocabulary, .setup]
    }

    private func moveSection(_ delta: Int) {
        let order = sidebarOrder
        let current = app.mainSection.flatMap { order.firstIndex(of: $0) } ?? -1
        app.mainSection = order[max(0, min(order.count - 1, current + delta))]
    }

    /// A sidebar row: selected, it sits on a bg300 pill with fg text.
    private func sidebarItem<Label: View>(_ section: MainSection, @ViewBuilder _ label: () -> Label) -> some View {
        let selected = app.mainSection == section
        return label()
            .foregroundStyle(Palette.fg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Palette.bg300 : Color.clear).padding(.horizontal, -4))
            .contentShape(Rectangle())
            .onTapGesture { app.mainSection = section }
            .listRowInsets(EdgeInsets(top: 1, leading: 0, bottom: 1, trailing: 0))
            .listRowBackground(Color.clear)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder private var detail: some View {
        switch app.mainSection {
        case .track(let id):
            if let index = app.store.tracks.firstIndex(where: { $0.id == id }) {
                TrackDetailView(app: app, track: Bindable(app.store).tracks[index]) {
                    app.store.tracks.remove(at: index)
                    // With no tracks left, stay here: the page below offers to lay a new one.
                    app.mainSection = app.store.tracks.first.map { .track($0.id) } ?? .track(id)
                }
                .id(id)
                .navigationTitle(app.store.tracks[index].name)
            } else {
                WranglerEmptyState(headline: "no pipes laid", pose: .sing,
                                   message: app.store.tracks.isEmpty
                                       ? "A track is a hotkey plus a pipeline: mic in, text or speech out. Start from a ready-made one or build your own."
                                       : "Pick a track in the sidebar, or lay a new one.",
                                   action: ("+ New track", newTrack),
                                   secondary: app.store.tracks.isEmpty ? ("Restore the starter tracks", restoreStarters) : nil)
                    .background(Palette.bg100)
            }
        case .activity:
            HistoryView(app: app).navigationTitle("History").background(Palette.bg100)
        case .vocabulary:
            VocabularyView(parakeet: app.parakeet, app: app).scrollsSidewaysBelow(520).navigationTitle("Vocabulary").background(Palette.bg100)
        case .setup, nil:
            SetupView(app: app).navigationTitle("Setup")
        }
    }

    private func restoreStarters() {
        app.store.restoreStarters()
        app.mainSection = app.store.tracks.first.map { .track($0.id) } ?? .setup
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
    @State private var copiedLog: RunRecord.ID?
    @State private var confirmingClear = false
    /// Runs whose log is open (several can be).
    @State private var open: Set<RunRecord.ID> = HistoryPreview.open
    /// What's loaded from the database so far, newest first; more loads as the end scrolls into view.
    @State private var loaded: [(seq: Int64, record: RunRecord)] = []
    @State private var matching = 0
    @State private var presentTracks: [String] = []
    private static let pageSize = 100

    private var records: [RunRecord] { loaded.map(\.record) }
    private var history: HistoryStore { app.historyStore }
    private var dbQuery: HistoryDatabase.Query { HistoryDatabase.Query(track: trackFilter, search: query) }

    /// Track names that appear in History, in the sidebar's order, then any others (renamed or deleted tracks).
    private var trackNames: [String] {
        let present = Set(presentTracks)
        let ordered = app.store.tracks.map(\.name).filter(present.contains)
        return ordered + present.subtracting(ordered).sorted()
    }

    /// The first page again (filters changed, a run was added). Keeps at least as many as were showing.
    private func reload(atLeast: Int = 0) {
        let limit = max(Self.pageSize, atLeast, loaded.count)
        loaded = history.database?.runs(dbQuery, limit: limit) ?? []
        matching = history.database?.count(dbQuery) ?? 0
        presentTracks = history.database?.trackNames() ?? []
    }

    private func loadMore() {
        guard loaded.count < matching, let last = loaded.last?.seq else { return }
        var next = dbQuery
        next.before = last
        loaded += history.database?.runs(next, limit: Self.pageSize) ?? []
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
            if history.count == 0 {
                let hotkey = app.store.tracks.first { $0.enabled && !$0.triggers.isEmpty }?.triggers.first?.combo.display
                WranglerEmptyState(headline: "quiet on the range",
                                   message: hotkey.map { "No runs yet. Hold \($0) and say something; every run lands here so you can copy it again." }
                                       ?? "No runs yet. Run a track and say something; every run lands here so you can copy it again.")
            } else {
                // The page's width decides a row's layout: below 560 pt of card, its buttons go under its text.
                GeometryReader { page in
                let narrow = page.size.width - 56 < 560
                ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        UsageTotalsStrip(records: history.lastWeek)
                        filters(narrow: page.size.width - 56 < 600)
                        if records.isEmpty {
                            Text("Nothing matches. Try fewer words, or All.").font(VPFont.caption).foregroundStyle(Palette.fgMuted)
                        }
                        ForEach(days, id: \.0) { day in
                            VStack(alignment: .leading, spacing: 8) {
                                SectionLabel(day.0)
                                // A card per run; an open run shows its log under it, with a purple border.
                                ForEach(day.1) { record in
                                    runCard(record, narrow: narrow).id("run-\(record.id)").vpFlash("run-\(record.id)", cornerRadius: 6)
                                }
                            }
                        }
                        if loaded.count < matching {
                            // Reaching the end loads the next page.
                            Text("Loading older runs…").font(VPFont.caption).foregroundStyle(Palette.fgMuted)
                                .onAppear(perform: loadMore)
                        }
                    }
                    .padding(.horizontal, 28).padding(.vertical, 24)
                    .frame(maxWidth: 900, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onAppear { takeRequest(proxy) }
                .onChange(of: UINav.shared.history) { _, _ in takeRequest(proxy) }
                }
                }
                .toolbar {
                    ToolbarItem {
                        Button("Clear history…") { confirmingClear = true }
                    }
                }
            }
        }
        .background(Palette.bg100)
        .onAppear { reload(); report() }
        .onChange(of: trackFilter) { _, _ in loaded = []; reload(); report() }
        .onChange(of: query) { _, _ in loaded = []; reload(); report() }
        .onChange(of: history.revision) { _, _ in reload() }
        .confirmationDialog("Clear all \(history.count.formatted()) runs from History?", isPresented: $confirmingClear) {
            Button("Clear history", role: .destructive) { app.historyStore.clear() }
        } message: {
            Text("This can't be undone.")
        }
    }

    /// `vp open history --track <id> --search <text> --run <n>`.
    private func takeRequest(_ proxy: ScrollViewProxy) {
        guard let request = UINav.shared.history else { return }
        UINav.shared.history = nil
        trackFilter = request.track
        query = request.search ?? ""
        loaded = []
        reload()
        guard let run = request.run else { return }
        // A run outside the filter isn't shown: show everything so it is. An older one: load down to it.
        if !records.contains(where: { $0.id == run }) {
            trackFilter = nil
            query = ""
            reload(atLeast: (history.database?.position(of: run) ?? 0) + 20)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo("run-\(run)", anchor: .center) }
            UINav.shared.highlight("run-\(run)")
        }
    }

    private func report() {
        UINav.shared.historyTrack = trackFilter
        UINav.shared.historySearch = query
    }

    /// Search and track chips; narrow, search gets its own line and the chips wrap (never truncated).
    @ViewBuilder private func filters(narrow: Bool) -> some View {
        let search = VPTextField("Search everything you've said", text: $query).focusKey("search")
        let chips = ForEach(["All"] + Array(trackNames.prefix(5)), id: \.self) { name in
            VPChip(title: name, selected: name == "All" ? trackFilter == nil : trackFilter == name) {
                trackFilter = name == "All" || trackFilter == name ? nil : name
            }
            .fixedSize()
        }
        if narrow {
            VStack(alignment: .leading, spacing: 8) {
                search
                FlowLayout(spacing: 8) { chips }
            }
        } else {
            HStack(spacing: 8) {
                search.frame(maxWidth: 300)
                chips
                Spacer(minLength: 8)
                Text(matching == history.count ? "\(history.count.formatted()) runs · on this Mac" : "\(matching.formatted()) of \(history.count.formatted()) runs").font(VPFont.caption).foregroundStyle(Palette.fgMuted)
                    .lineLimit(1).fixedSize()
            }
        }
    }

    private func runCard(_ record: RunRecord, narrow: Bool) -> some View {
        let isOpen = open.contains(record.id)
        return VStack(alignment: .leading, spacing: 0) {
            row(record, isOpen: isOpen, narrow: narrow)
            if isOpen, record.log != nil {
                Hairline()
                RunLogView(record: record)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(record.failure != nil ? Palette.bg300 : Palette.bg200))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(isOpen ? Palette.purple : Palette.line, lineWidth: 1))
    }

    private func toggle(_ record: RunRecord) {
        if open.contains(record.id) { open.remove(record.id) } else { open.insert(record.id) }
    }

    /// "· $0.0027 + ≈$0.0004", "· on this Mac", "· 1 step passed its input through" after the track and time.
    private func usageMeta(_ record: RunRecord) -> Text {
        guard record.log != nil else { return Text("") }
        let summary = UsageSummary([record])
        var text = Text("")
        if summary.exact > 0 || summary.estimated > 0 {
            if summary.exact > 0 {
                text = text + Text(" · ") + Text(" \(RunLogFormat.cost(summary.exact)) ").bold().foregroundColor(Palette.fg)
            }
            if summary.estimated > 0 {
                text = text + Text(summary.exact > 0 ? " + " : " · ") + Text("≈\(RunLogFormat.cost(summary.estimated))")
            }
        } else if !summary.usedCloud {
            text = text + Text(" · on this Mac")
        }
        let passed = record.passedThroughCount
        if passed > 0 {
            text = text + Text(" · \(passed) step\(passed == 1 ? "" : "s") passed \(passed == 1 ? "its" : "their") input through").foregroundColor(Palette.orange)
        }
        return text
    }

    private func row(_ record: RunRecord, isOpen: Bool, narrow: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            rowBody(record, isOpen: isOpen, showButtons: !narrow)
            if narrow { rowButtons(record, isOpen: isOpen).padding(.leading, record.log != nil ? 28 : 0) }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        // The header toggles the log (text inside stays selectable); a focused row opens with → and closes with ←.
        .contentShape(Rectangle())
        .onTapGesture { if record.log != nil { toggle(record) } }
        .focusable(record.log != nil)
        .onKeyPress(.rightArrow) {
            guard record.log != nil, !open.contains(record.id) else { return .ignored }
            open.insert(record.id)
            return .handled
        }
        .onKeyPress(.leftArrow) {
            guard open.contains(record.id) else { return .ignored }
            open.remove(record.id)
            return .handled
        }
    }

    private func rowButtons(_ record: RunRecord, isOpen: Bool) -> some View {
        HStack(spacing: 8) {
            if isOpen {
                Button(copiedLog == record.id ? "Copied ✓" : "Copy log") {
                    Clipboard.shared.copy(record.logText)
                    copiedLog = record.id
                }
                .buttonStyle(copiedLog == record.id ? VPButtonStyle(kind: .primary) : VPButtonStyle(kind: .secondary))
            }
            Button(copied == record.id ? "Copied ✓" : "Copy") {
                Clipboard.shared.copy(record.text)
                copied = record.id
            }
            .buttonStyle(copied == record.id ? VPButtonStyle(kind: .primary) : VPButtonStyle(kind: .secondary))
        }
    }

    private func rowBody(_ record: RunRecord, isOpen: Bool, showButtons: Bool) -> some View {
        let failed = record.failure != nil
        let color = failed ? Palette.orange
            : (record.colorHex ?? app.store.tracks.first { $0.name == record.trackName }?.colorHex).map(Palette.track) ?? Palette.fgMuted
        return HStack(alignment: .top, spacing: 12) {
            if record.log != nil {
                Button { toggle(record) } label: {
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(isOpen ? Palette.purple : Palette.fgMuted)
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isOpen ? "Hide run log" : "Show run log")
                .help(isOpen ? "Hide the log" : "Show how this run went, step by step")
            }
            VStack(alignment: .leading, spacing: 6) {
                // The square sits on the first line when the meta line wraps.
                HStack(alignment: .top, spacing: 8) {
                    Rectangle().fill(color).frame(width: 7, height: 7).padding(.top, 4)
                    (Text("\(record.trackName) · \(record.date.formatted(date: .omitted, time: .shortened)) · \(record.totalMs.msLabel)")
                        + usageMeta(record)
                        + (record.failure.map { Text(" · " + $0).foregroundColor(Palette.orange) } ?? Text("")))
                        .font(VPFont.caption).foregroundStyle(Palette.fgMuted).fixedSize(horizontal: false, vertical: true)
                }
                if let heard = record.heard {
                    Text("› " + heard).foregroundStyle(Palette.fgMuted).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(record.text).lineSpacing(3).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                if !record.steps.isEmpty { StepChain(steps: record.steps) }
            }
            Spacer(minLength: 0)
            if showButtons { rowButtons(record, isOpen: isOpen) }
        }
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

/// The shared word list used by Fix words steps (and given to LLM steps as a glossary).
/// A plain table rather than a Form: Form shows a text field's title as a label beside it.
private struct VocabularyView: View {
    let parakeet: ParakeetService
    let app: AppState
    @Bindable private var store = VocabularyStore.shared
    @State private var training: VocabularyEntry.ID?
    @State private var sample = "i use cloud code and open router every day."
    @State private var askingWord = false
    @State private var newWord = ""

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Words transcription keeps getting wrong. **Write** is the spelling you want; **Heard as** lists what comes out instead, separated by commas. Replacement is mechanical and instant: whole words only, any capitalization. Spellings with capitals are always written exactly; all-lowercase ones get a capital at the start of a sentence unless **Always exact** is on.")
                    .font(VPFont.caption).lineSpacing(3).foregroundStyle(Palette.fgMuted)
                    .fixedSize(horizontal: false, vertical: true)

                if store.entries.isEmpty {
                    WranglerEmptyState(headline: "nothing to rope yet", scale: 4,
                                       message: "Add a word transcription keeps getting wrong, like a name or a product, and Fix words will spell it your way from then on.",
                                       action: ("+ Add word", { store.entries.append(VocabularyEntry(write: "", heardAs: [])) }),
                                       secondary: ("Train a word…", { askingWord = true }))
                        .frame(minHeight: 360)
                        .vpCard()
                } else {
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
                                        .id("vocab-\(entry.id)")
                                        .vpFlash("vocab-\(entry.id)")
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
                }

                VPSection("Try it") {
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            VPTextField("Type or paste a sentence", text: $sample, axis: .vertical).focusKey("try")
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
        .onAppear { takeRequest(proxy) }
        .onChange(of: UINav.shared.vocabulary) { _, _ in takeRequest(proxy) }
        }
        .onChange(of: UINav.shared.dismissSheets) { _, _ in askingWord = false; training = nil }
        .onChange(of: askingWord) { _, _ in reportSheet() }
        .onChange(of: training) { _, _ in reportSheet() }
        .onDisappear { UINav.shared.sheet = nil }
        .onAppear(perform: takePendingTraining)
        .onChange(of: app.pendingTraining) { _, _ in takePendingTraining() }
        .sheet(isPresented: $askingWord) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Which word?").font(VPFont.title)
                Text("The spelling you want, e.g. a name or a product. Then say it a few times.")
                    .font(VPFont.caption).foregroundStyle(Palette.fgMuted)
                VPTextField("Spelling", text: $newWord, onSubmit: startTraining)
                HStack {
                    Spacer()
                    Button("Cancel") { askingWord = false }.buttonStyle(.vpSecondary).keyboardShortcut(.cancelAction)
                    Button("Continue", action: startTraining).buttonStyle(.vpPrimary).keyboardShortcut(.defaultAction)
                        .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(24)
            .frame(width: 420)
            .background(Palette.bg100)
            .vpWindow()
        }
        .sheet(isPresented: Binding { training != nil } set: { if !$0 { training = nil } }) {
            if let index = store.entries.firstIndex(where: { $0.id == training }) {
                TrainWordSheet(parakeet: parakeet, entry: $store.entries[index])
            }
        }
    }

    /// `vp open vocabulary --word <w>` scrolls to the word; `--add` asks for a new one.
    private func takeRequest(_ proxy: ScrollViewProxy) {
        guard let request = UINav.shared.vocabulary else { return }
        UINav.shared.vocabulary = nil
        if request.add { askingWord = true }
        guard let word = request.word, let entry = store.entries.first(where: { $0.write.lowercased() == word.lowercased() }) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo("vocab-\(entry.id)", anchor: .center) }
            UINav.shared.highlight("vocab-\(entry.id)")
        }
    }

    private func reportSheet() {
        UINav.shared.sheet = askingWord ? "add-word"
            : training.flatMap { id in store.entries.first { $0.id == id } }.map { "train:\($0.write)" }
    }

    /// `vp vocab train <word>`: open that word's training.
    private func takePendingTraining() {
        guard let word = app.pendingTraining else { return }
        app.pendingTraining = nil
        if let entry = store.entries.first(where: { $0.write.lowercased() == word.lowercased() }) { training = entry.id }
    }

    /// Adds the word and opens training for it, once the "Which word?" sheet has closed.
    private func startTraining() {
        let word = newWord.trimmingCharacters(in: .whitespaces)
        guard !word.isEmpty else { return }
        let entry = VocabularyEntry(write: word, heardAs: [])
        store.entries.append(entry)
        newWord = ""
        askingWord = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { training = entry.id }
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
        // `vp open --background` shows the window without taking the keyboard from the app you're in.
        if !UINav.shared.quietOpen { NSApp.activate(ignoringOtherApps: true) }
    }

    /// Back to menu-bar-only once the last of the main and About windows has closed.
    static func closed() {
        DispatchQueue.main.async {
            let open = NSApp.windows.contains { window in
                window.isVisible && (["main", "about"].contains { window.identifier?.rawValue.hasPrefix($0) ?? false }
                    || window.title == OnboardingController.title)
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

/// Harness only: runs to show with their logs open.
enum HistoryPreview {
    #if SNAPSHOTS
    nonisolated(unsafe) static var open: Set<RunRecord.ID> = []
    #else
    static let open: Set<RunRecord.ID> = []
    #endif
}

/// The window's bottom bar: the version line on a 28-point strip.
struct VersionFooter: View {
    var body: some View {
        VStack(spacing: 0) {
            Hairline()
            VersionLine()
                .padding(.horizontal, 16)
                .frame(height: 28)
                .background(Palette.bg000)
        }
    }
}

/// Which version is running, and whether it's the newest (Check now / Install…). The window's bottom bar and the
/// menu bar panel's last line.
struct VersionLine: View {
    @EnvironmentObject var updates: Updates

    var body: some View {
        HStack(spacing: 0) {
            Text("Voice Pipes \(updates.version)").foregroundStyle(Palette.fgMuted)
            status
            Spacer(minLength: 12)
            action
        }
        .font(VPFont.caption).lineLimit(1)
        .onAppear { updates.poll() }
    }

    @ViewBuilder private var status: some View {
        if let available = updates.available {
            Text(" · \(available) available").foregroundStyle(Palette.purple)
        } else if !updates.enabled {
            Text(" · updates off in this build").foregroundStyle(Palette.comment).help(Updates.noFeed)
        } else if updates.checking {
            Text(" · checking…").foregroundStyle(Palette.comment)
        } else if let checked = updates.checkedAt {
            Text(" · up to date").foregroundStyle(Palette.comment)
                .help("Up to date as of \(checked.formatted(date: .omitted, time: .shortened))")
        }
    }

    @ViewBuilder private var action: some View {
        if updates.available != nil {
            Button("Install…") { updates.check() }.buttonStyle(.plain)
                .font(VPFont.label).foregroundStyle(Palette.purple)
                .help("Downloads, checks the signature and relaunches; takes a few seconds")
        } else if updates.enabled {
            Button("Check now") { updates.poll(force: true) }.buttonStyle(.plain)
                .font(VPFont.label).foregroundStyle(updates.checking ? Palette.comment : Palette.purple)
                .disabled(updates.checking)
        }
    }
}
