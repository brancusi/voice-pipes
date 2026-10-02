import SwiftUI

/// Permissions, connections, models and updates in one place: cards of log-style rows (OK, INFO, WARN, FAIL).
struct SetupView: View {
    let app: AppState
    @EnvironmentObject var updates: Updates
    private var catalog: OpenRouterCatalog { .shared }
    @AppStorage(AppearanceChoice.defaultsKey) private var appearance = AppearanceChoice.auto.rawValue

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    checks.vpSetupSection("checks")
                    connections.vpSetupSection("connections")
                    VPSection("Command line and agents") { Card { CommandLineCard() } }.vpSetupSection("cli")
                    onThisMac.vpSetupSection("models")
                    appearanceSection.vpSetupSection("appearance")
                    ReadingSettingsSection(app: app).vpSetupSection("reading")
                    updatesSection.vpSetupSection("updates")
                }
                .padding(.horizontal, 32).padding(.vertical, 24)
                .frame(maxWidth: 900, alignment: .leading)
            }
            .onAppear { takeRequest(proxy) }
            .onChange(of: UINav.shared.setupSection) { _, _ in takeRequest(proxy) }
        }
        .background(Palette.bg100)
        .toolbar {
            ToolbarItem { Button("Run setup again…") { OnboardingController.shared.show(app) } }
            ToolbarItem { Button("Copy report") { app.copyReport() } }
        }
        .onAppear { if app.openRouterKeyState == nil { app.checkOpenRouterKey() } }
    }

    /// `vp open setup --section <name>`.
    static let sections = ["checks", "connections", "cli", "models", "appearance", "reading", "updates"]

    private func takeRequest(_ proxy: ScrollViewProxy) {
        guard let section = UINav.shared.setupSection else { return }
        UINav.shared.setupSection = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo("setup-\(section)", anchor: .top) }
            UINav.shared.highlight("setup-\(section)")
        }
    }

    // MARK: Sections

    private var checks: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionLabel("Checks")
                Spacer()
                if app.checking { ProgressView().controlSize(.small) }
                Button("↻ Check again") { app.refreshChecks() }.buttonStyle(.vpGhost)
            }
            Card {
                ForEach(Array(app.checks.enumerated()), id: \.element.id) { index, check in
                    if index > 0 { Hairline() }
                    HStack(spacing: 12) {
                        StatusCode(level: check.level)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(check.title)
                            if !check.detail.isEmpty {
                                Text(check.detail).font(VPFont.caption).foregroundStyle(Palette.fgMuted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer()
                        if let fix = check.fix, fix != .editTracks {
                            Button(fix == .openConfig ? "Open file…" : "Fix…") { app.fix(fix) }.buttonStyle(.vpGhost)
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 9)
                }
            }
        }
    }

    private var connections: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Connections")
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    ConnectionHeader(name: "OpenRouter", purpose: "Cloud transcription, LLM and speech models",
                                     status: openRouterStatus)
                    KeyField(hint: app.openRouterKeyHint, placeholder: "Paste your OpenRouter key (sk-or-…)",
                             failed: app.openRouterKeyState == .rejected, focusKey: "openrouter-key") { app.setOpenRouterKey($0) }
                    HStack(spacing: 10) {
                        if catalog.loading { ProgressView().controlSize(.small) }
                        Text(catalogLine).font(VPFont.caption).foregroundStyle(Palette.fgMuted)
                        Spacer()
                        Button("↻ Reload models") { catalog.refresh() }.buttonStyle(.vpGhost)
                        if app.hasOpenRouterKey {
                            Button { app.setOpenRouterKey("") } label: { Text("Remove key").foregroundStyle(Palette.fgMuted) }
                                .buttonStyle(.vpGhost)
                        }
                    }
                    if let error = catalog.error {
                        Text(error).font(VPFont.caption).foregroundStyle(Palette.orange)
                    }
                }
                .padding(14)
                Hairline()
                VStack(alignment: .leading, spacing: 10) {
                    ConnectionHeader(name: "TypeSafe · Jev",
                                     purpose: "Picks the model in Route steps; judges mishearings when you train a word",
                                     status: app.hasJevKey ? (.ok, "saved") : (.info, "not set"))
                    KeyField(hint: app.jevKeyHint, placeholder: "Paste your TypeSafe key", failed: false, focusKey: "typesafe-key") { app.setJevKey($0) }
                    if app.hasJevKey {
                        HStack {
                            Spacer()
                            Button { app.setJevKey("") } label: { Text("Remove key").foregroundStyle(Palette.fgMuted) }
                                .buttonStyle(.vpGhost)
                        }
                    }
                }
                .padding(14)
            }
        }
    }

    private var onThisMac: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("On this Mac")
            Card {
                ModelRow(name: "Parakeet v3", detail: "transcription · 480 MB", state: parakeetState, load: nil,
                         download: app.parakeetState == .loading ? ModelDownloads.shared.status[.parakeet] ?? .init(total: ModelDownloads.Model.parakeet.totalBytes) : nil)
                ForEach(LocalVoiceEngine.allCases) { engine in
                    Hairline()
                    let state = app.localVoiceStates[engine] ?? .notLoaded
                    ModelRow(name: engine.label, detail: "speech · \(engine.voices.count) voices · \(engine == .pocket ? 530 : 170) MB",
                             state: Self.modelState(state),
                             load: canLoad(state) ? { Task { try? await LocalVoices.shared.prepare(engine) } } : nil,
                             download: state == .loading ? ModelDownloads.shared.status[.init(engine)] ?? .init(total: ModelDownloads.Model(engine).totalBytes) : nil)
                }
            }
        }
    }

    private var appearanceSection: some View {
        let choice = Binding<AppearanceChoice> {
            AppearanceChoice(rawValue: appearance) ?? .auto
        } set: { appearance = $0.rawValue }
        return VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Appearance")
            Card {
                let picker = VStack(alignment: .leading, spacing: 10) {
                    VPSegmented(selection: choice, options: AppearanceChoice.allCases.map { ($0, $0.label) })
                    Text(choice.wrappedValue.detail + " The HUD stays dark.")
                        .font(VPFont.caption).foregroundStyle(Palette.fgMuted)
                }
                let swatches = HStack(spacing: 28) {
                    ThemeSwatch(name: "Daylight", dark: false, selected: choice.wrappedValue == .daylight) { choice.wrappedValue = .daylight }
                    ThemeSwatch(name: "Sundown", dark: true, selected: choice.wrappedValue == .sundown) { choice.wrappedValue = .sundown }
                }
                // Side by side when there's room; the swatches go underneath in a narrow window.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 28) { picker.frame(minWidth: 300, alignment: .leading); Spacer(minLength: 0); swatches }
                    VStack(alignment: .leading, spacing: 16) { picker; swatches }
                }
                .padding(16)
            }
        }
        .onChange(of: appearance) { _, value in
            AppearanceChoice.apply(AppearanceChoice(rawValue: value) ?? .auto)
            app.store.saveConfig()  // settings.appearance in config.toml
        }
    }

    private var updatesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Updates")
            Card {
                HStack(spacing: 12) {
                    StatusCode(level: updates.enabled ? .ok : .info)
                    Text("Voice Pipes \(updates.version)")
                    Spacer()
                    Text(updates.enabled ? "signed, notarized · checks every few minutes" : "updates are off in this build")
                        .font(VPFont.caption).foregroundStyle(Palette.fgMuted)
                    Button("Check now") { updates.check() }.buttonStyle(.vpSecondary).disabled(!updates.enabled)
                }
                .padding(.horizontal, 14).padding(.vertical, 9)
            }
        }
    }

    // MARK: Helpers

    private var openRouterStatus: (Check.Level, String) {
        guard app.hasOpenRouterKey else { return (.info, "not set") }
        return switch app.openRouterKeyState {
        case .checking, nil: (.info, "checking…")
        case .valid: (.ok, "key valid")
        case .rejected: (.problem, "OpenRouter rejected it")
        case .unreachable: (.warning, "can't reach openrouter.ai")
        }
    }

    private var catalogLine: String {
        guard !catalog.models.isEmpty else { return "Models not loaded" }
        let text = catalog.models(for: .text).count, stt = catalog.models(for: .transcription).count
        let speech = catalog.models(for: .speech).count
        let when = catalog.updated.map { " · updated \($0.shortAgo)" } ?? ""
        return "\(text) language · \(stt) transcription · \(speech) speech models\(when)"
    }

    private var parakeetState: (Check.Level, String) {
        switch app.parakeetState {
        case .notLoaded: (.info, "loads on first use")
        case .loading: (.info, "loading…")
        case .ready: (.ok, "loaded")
        case .failed(let error): (.problem, "failed: \(error)")
        }
    }

    static func modelState(_ state: LocalVoices.State) -> (Check.Level, String) {
        switch state {
        case .notLoaded: (.info, "loads on first use")
        case .loading: (.info, "downloading / loading…")
        case .ready: (.ok, "loaded")
        case .failed(let error): (.problem, "failed: \(error)")
        }
    }

    private func canLoad(_ state: LocalVoices.State) -> Bool {
        switch state {
        case .notLoaded, .failed: true
        case .loading, .ready: false
        }
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
}

private struct ConnectionHeader: View {
    let name: String
    let purpose: String
    let status: (Check.Level, String)

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(name).font(VPFont.bodyStrong).lineLimit(1).fixedSize()
            // The purpose gives way first in a narrow window; the name and status never wrap.
            Text(purpose).font(VPFont.caption).foregroundStyle(Palette.fgMuted).lineLimit(1).truncationMode(.tail)
                .layoutPriority(-1)
            Spacer(minLength: 12)
            Text(SetupView.code(status.0)).font(VPFont.label).tracking(0.9).foregroundStyle(MenuView.color(status.0)).fixedSize()
            Text(status.1).font(VPFont.caption).foregroundStyle(Palette.fgMuted).lineLimit(1)
        }
    }
}

private struct ModelRow: View {
    let name: String
    let detail: String
    let state: (Check.Level, String)
    let load: (() -> Void)?
    var download: ModelDownloads.Status?

    var body: some View {
        HStack(spacing: 12) {
            StatusCode(level: state.0)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                Text(detail).font(VPFont.caption).foregroundStyle(Palette.fgMuted)
                if let download { ModelLoadBar(status: download).padding(.top, 5).frame(maxWidth: 360) }
            }
            Spacer(minLength: 8)
            Text(state.1).font(VPFont.caption).foregroundStyle(Palette.fgMuted).lineLimit(1)
            if let load { Button("Load now", action: load).buttonStyle(.vpGhost) }
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
    }
}

/// An API key field with no Save button. It shows the saved key masked; pasting a new key (or typing one and
/// pressing Return) replaces it in the Keychain at once. Esc leaves it as it was.
struct KeyField: View {
    let hint: String?
    let placeholder: String
    let failed: Bool
    var focusKey: String? = nil
    let save: (String) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(hint ?? placeholder).foregroundStyle(hint == nil ? Palette.comment : Palette.fg)
                        .lineLimit(1).allowsHitTesting(false)
                }
                SecureField("", text: $text)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit(commit)
                    .onExitCommand { text = ""; focused = false }
            }
            if let note {
                Text(note.0).font(VPFont.caption).foregroundStyle(note.1).fixedSize()
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 4).fill(Palette.bg000))
        .overlay(RoundedRectangle(cornerRadius: 4)
            .strokeBorder(focused ? Palette.pink : failed ? Palette.red : Palette.line, lineWidth: focused ? 2 : 1))
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .modifier(FocusKeyModifier(key: focusKey, focused: $focused))
        // A paste arrives as one big change; save it straight away. Typing waits for Return.
        .onChange(of: text) { old, new in if new.count - old.count >= 8 { commit() } }
    }

    private var note: (String, Color)? {
        if focused { return ("paste a new key · esc", Palette.pink) }
        guard hint != nil else { return nil }
        return failed ? ("paste again", Palette.red) : ("⌘V to replace", Palette.fgMuted)
    }

    private func commit() {
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines)
        text = ""
        guard !key.isEmpty else { return }
        save(key)
        focused = false
    }
}

/// A small preview of a theme: its window ground, a line of text, a hairline and the accent. Clicking it picks it.
private struct ThemeSwatch: View {
    let name: String
    let dark: Bool
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 4) {
                    Rectangle().fill(Color(hex: dark ? 0xF0E4CC : 0x2A211B)).frame(width: 45, height: 6)
                    Rectangle().fill(Color(hex: dark ? 0x4A3F35 : 0xD3C2A3)).frame(width: 60, height: 6)
                    Rectangle().fill(Color(hex: dark ? 0xC3A3D4 : 0x6C4A86)).frame(width: 30, height: 6)
                }
                .padding(8)
                .frame(width: 92, height: 58, alignment: .topLeading)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color(hex: dark ? 0x1F1A15 : 0xF7EEDC)))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(selected ? Palette.purple : Palette.line, lineWidth: selected ? 2 : 1))
                Text(name).font(VPFont.caption).foregroundStyle(selected ? Palette.fg : Palette.fgMuted)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name) theme")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

private extension View {
    func vpSetupSection(_ name: String) -> some View {
        id("setup-\(name)").vpFlash("setup-\(name)")
    }
}

/// Setup → Reading: when the HUD takes the keyboard while something is read aloud, what clicking away does, the
/// keys for each action, and shortcuts that work anywhere while reading. Saved in config.toml [settings.reading].
private struct ReadingSettingsSection: View {
    let app: AppState

    private var reading: Binding<ReadingSettings> {
        Binding { app.store.reading } set: { app.store.reading = $0 }
    }

    private static let modeDetail: [ReadingSettings.TakeKeys: String] = [
        .always: "As soon as something is read aloud, its keys work. Your app stays in front; click it to type again.",
        .hover: "Move the pointer onto the HUD, or click it, and its keys work. Move away and they're yours again.",
        .click: "Click the HUD and its keys work; click anywhere else to give them back.",
        .never: "Only the buttons and any shortcuts below.",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Reading")
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Keyboard while reading").font(VPFont.bodyStrong)
                        VPSegmented(selection: reading.takeKeys, options: ReadingSettings.TakeKeys.allCases.map { ($0, $0.label) })
                        Text(Self.modeDetail[reading.wrappedValue.takeKeys] ?? "").font(VPFont.caption).foregroundStyle(Palette.fgMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("When I click away").font(VPFont.bodyStrong)
                        VPSegmented(selection: reading.clickAway, options: [(.keepReading, "Keep reading"), (.stop, "Stop")])
                    }
                    Hairline()
                    HStack {
                        Text("Keys while the HUD has the keyboard").font(VPFont.bodyStrong)
                        Spacer()
                        Button("Reset to defaults") { reading.wrappedValue.keys = ReadingSettings.defaultKeys }
                            .buttonStyle(.vpGhost)
                            .disabled(reading.wrappedValue.keys == ReadingSettings.defaultKeys)
                    }
                    ForEach(ReadingSettings.Action.allCases) { action in
                        actionRow(action.label) {
                            ForEach(Array((reading.wrappedValue.keys[action] ?? []).enumerated()), id: \.offset) { index, combo in
                                RemovableKeycap(combo: combo) { reading.wrappedValue.keys[action]?.remove(at: index) }
                            }
                            KeyCaptureButton(title: "+ key", app: app) { combo in
                                if !(reading.wrappedValue.keys[action] ?? []).contains(combo) { reading.wrappedValue.keys[action, default: []].append(combo) }
                                return nil
                            }
                        }
                    }
                    Hairline()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Anywhere while reading").font(VPFont.bodyStrong)
                        Text("Shortcuts that work in any app, but only while something is being read. Include ⌃, ⌥ or ⌘ so they don't take a key from your typing.")
                            .font(VPFont.caption).foregroundStyle(Palette.fgMuted).fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(ReadingSettings.Action.allCases) { action in
                        actionRow(action.label) {
                            if let combo = reading.wrappedValue.global[action] {
                                RemovableKeycap(combo: combo) { reading.wrappedValue.global[action] = nil }
                            } else {
                                KeyCaptureButton(title: "Set…", app: app) { combo in
                                    guard !combo.modifiers.isEmpty else { return "needs ⌃, ⌥ or ⌘" }
                                    reading.wrappedValue.global[action] = combo
                                    return nil
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
    }

    private func actionRow<Keys: View>(_ label: String, @ViewBuilder keys: () -> Keys) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).font(VPFont.caption).foregroundStyle(Palette.fgMuted).frame(width: 150, alignment: .leading)
            FlowLayout(spacing: 6) { keys() }
        }
    }
}

/// A key in a list, with × to remove it.
private struct RemovableKeycap: View {
    let combo: KeyCombo
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            Keycap(text: combo.display)
            Button(action: onRemove) { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                .buttonStyle(.plain).foregroundStyle(Palette.fgMuted).frame(width: 16, height: 22)
                .help("Remove \(combo.display)")
        }
    }
}

/// Click, then press a key (with or without modifiers) to add it. Esc cancels; your track hotkeys pause meanwhile.
/// `onCapture` returns a reason to refuse the key, or nil to accept it.
private struct KeyCaptureButton: View {
    let title: String
    let app: AppState
    let onCapture: (KeyCombo) -> String?
    @State private var recording = false
    @State private var monitor: Any?
    @State private var refusal: String?

    var body: some View {
        HStack(spacing: 6) {
            Button { recording ? stop() : start() } label: {
                Text(recording ? "Press a key…" : title)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(recording ? Palette.pink : Palette.purple)
                    .padding(.horizontal, 8).frame(height: 22)
                    .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(recording ? Palette.pink : Palette.line, lineWidth: 1))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if let refusal { Text(refusal).font(VPFont.caption).foregroundStyle(Palette.orange) }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        refusal = nil
        app.hotkeysSuspended = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53, event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
                stop()  // plain Esc cancels
            } else {
                refusal = onCapture(KeyCombo(key: .init(code: UInt32(event.keyCode)), modifiers: .init(event.modifierFlags)))
                stop()
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording { app.hotkeysSuspended = false }
        recording = false
    }
}
