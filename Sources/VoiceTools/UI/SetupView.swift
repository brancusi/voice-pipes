import SwiftUI

/// Permissions, connections, models and updates in one place: cards of log-style rows (OK, INFO, WARN, FAIL).
struct SetupView: View {
    let app: AppState
    @EnvironmentObject var updates: Updates
    private var catalog: OpenRouterCatalog { .shared }
    @AppStorage(AppearanceChoice.defaultsKey) private var appearance = AppearanceChoice.auto.rawValue

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                checks
                connections
                onThisMac
                appearanceSection
                updatesSection
            }
            .padding(.horizontal, 32).padding(.vertical, 24)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .background(Palette.bg100)
        .toolbar {
            ToolbarItem { Button("Run setup again…") { OnboardingController.shared.show(app) } }
            ToolbarItem { Button("Copy report") { app.copyReport() } }
        }
        .onAppear { if app.openRouterKeyState == nil { app.checkOpenRouterKey() } }
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
                             failed: app.openRouterKeyState == .rejected) { app.setOpenRouterKey($0) }
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
                    KeyField(hint: app.jevKeyHint, placeholder: "Paste your TypeSafe key", failed: false) { app.setJevKey($0) }
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
                ModelRow(name: "Parakeet v3", detail: "transcription · ~460 MB", state: parakeetState, load: nil)
                ForEach(LocalVoiceEngine.allCases) { engine in
                    Hairline()
                    let state = app.localVoiceStates[engine] ?? .notLoaded
                    ModelRow(name: engine.label, detail: "speech · \(engine.voices.count) voices",
                             state: Self.modelState(state),
                             load: canLoad(state) ? { Task { try? await LocalVoices.shared.prepare(engine) } } : nil)
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

    var body: some View {
        HStack(spacing: 12) {
            StatusCode(level: state.0)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                Text(detail).font(VPFont.caption).foregroundStyle(Palette.fgMuted)
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
