import AppKit
@preconcurrency import AVFoundation
import SwiftUI

/// First-run setup: welcome, permissions (with a drag-in helper for Privacy & Security), the on-device models
/// downloading in the background, optional API keys, and a place to try a hotkey. Shown on a first launch, or when
/// a permission is missing and setup was never finished; Setup → "Run setup again…" opens it any time.
enum Onboarding {
    static let doneKey = "onboarding.done.v1"

    static func shouldShow(freshInstall: Bool) -> Bool {
        guard !UserDefaults.standard.bool(forKey: doneKey) else { return false }
        return freshInstall || !AXIsProcessTrusted() || AVCaptureDevice.authorizationStatus(for: .audio) != .authorized
    }

    static func markDone() { UserDefaults.standard.set(true, forKey: doneKey) }
}

/// Hosts the setup window in AppKit, so it can open at launch without any SwiftUI scene being on screen.
@MainActor
final class OnboardingController {
    static let shared = OnboardingController()
    static let title = "Welcome to Voice Pipes"
    private var window: NSWindow?

    func show(_ app: AppState) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingView(rootView: OnboardingView(app: app) { [weak self] in self?.close() })
        // Sized before centring: a zero-sized window centres its corner, not itself.
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = OnboardingController.title
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.setContentSize(hosting.fittingSize)
        window.center()
        self.window = window
        var token: NSObjectProtocol?
        token = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            if let token { NotificationCenter.default.removeObserver(token) }
            Task { @MainActor in
                PermissionHelper.shared.hide()
                OnboardingController.shared.window = nil
                WindowBehavior.closed()
            }
        }
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() { window?.close() }
}

struct OnboardingView: View {
    let app: AppState
    let finish: () -> Void
    @State private var step: Step
    @State private var mic = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var trusted = AXIsProcessTrusted()
    @State private var voices: [LocalVoiceEngine: LocalVoices.State] = [:]
    @State private var tryText = ""
    /// Runs that finish after this time count as the "Try it" result.
    @State private var tryStarted = Date.distantFuture
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(app: AppState, step: Step = .welcome, finish: @escaping () -> Void) {
        self.app = app
        self.finish = finish
        _step = State(initialValue: step)
    }

    enum Step: Int, CaseIterable { case welcome, permissions, models, keys, agents, tryIt }

    static let contentSize = CGSize(width: SundownScene.size.width, height: 532)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if step == .welcome { SundownScene(layout: .welcome) }
            VStack(alignment: .leading, spacing: 16) {
                progress
                content
                Spacer(minLength: 0)
                footer
            }
            .padding(.horizontal, 32).padding(.top, step == .welcome ? 22 : 28).padding(.bottom, 24)
        }
        .frame(width: Self.contentSize.width, height: Self.contentSize.height)
        .background(Palette.bg100)
        .vpWindow()
        .onReceive(tick) { _ in refresh() }
        .onAppear(perform: refresh)
        .onChange(of: step) { _, new in
            if new == .tryIt { tryStarted = Date() }
            UINav.shared.currentOnboardingStep = new.rawValue
        }
        .onAppear { UINav.shared.currentOnboardingStep = step.rawValue; takeStep() }
        .onDisappear { UINav.shared.currentOnboardingStep = nil }
        .onChange(of: UINav.shared.onboardingStep) { _, _ in takeStep() }
    }

    /// `vp open onboarding --step <name>`.
    static let stepNames = ["welcome", "permissions", "models", "keys", "agents", "try"]

    private func takeStep() {
        guard let raw = UINav.shared.onboardingStep else { return }
        UINav.shared.onboardingStep = nil
        if let new = Step(rawValue: raw) { step = new }
    }

    /// Five segments: done in sage, the current step in lavender, the rest a hairline.
    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases, id: \.self) { item in
                Rectangle()
                    .fill(item == step ? Palette.purple : item.rawValue < step.rawValue ? Palette.green : Palette.line)
                    .frame(width: 28, height: 4)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(step.rawValue + 1) of \(Step.allCases.count)")
    }

    // MARK: Steps

    @ViewBuilder private var content: some View {
        switch step {
        case .welcome:
            PixelHeadline("howdy, partner", size: 28)
            Text("Voice Pipes turns your voice into text, answers and speech through pipelines you play from the keyboard. A few quick steps: allow the microphone and paste, load the on-device models, add keys if you want cloud models, optionally set up the command line for agents, and try it.")
                .font(VPFont.body).lineSpacing(5).foregroundStyle(Palette.fgMuted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 620, alignment: .leading)
        case .permissions:
            heading("Permissions", "Two switches in System Settings. Voice Pipes only listens while you hold or toggle a hotkey.")
            Card {
                permissionRow(name: "Microphone", detail: "To hear you while a track is recording.",
                              granted: mic == .authorized, next: mic != .authorized) {
                    if mic == .notDetermined {
                        Task {
                            _ = await AVCaptureDevice.requestAccess(for: .audio)
                            refresh()
                        }
                    } else {
                        PermissionHelper.shared.show(.microphone)
                        Self.openPrivacy("Privacy_Microphone")
                    }
                }
                Hairline()
                permissionRow(name: "Accessibility",
                              detail: "To paste at your cursor and read selected text. Click Allow, then switch on Voice Pipes in the list that opens.",
                              granted: trusted, next: mic == .authorized && !trusted) {
                    TextCapture.promptForAccessibility()
                    Self.openPrivacy("Privacy_Accessibility")
                    PermissionHelper.shared.show(.accessibility)
                }
            }
            if let waiting {
                Text("Waiting for \(waiting)… this page updates by itself when it's on.")
                    .font(.system(size: 12, design: .monospaced)).foregroundStyle(Palette.comment)
            }
        case .models:
            heading("On this Mac", "These run on your Mac with nothing sent anywhere. They download once and load in the background; you can keep going.")
            Card {
                parakeetRow
                Hairline()
                voiceRow(.pocket, detail: "read aloud · 26 voices · 770 MB", optional: false)
                Hairline()
                voiceRow(.supertonic, detail: "faster voices · 100 MB · optional", optional: true)
            }
        case .keys:
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Keys").font(VPFont.display)
                Text("optional").font(.system(size: 12, design: .monospaced)).foregroundStyle(Palette.fgMuted)
            }
            Text("Fast dictation and Read aloud work without any key. Add these for the cloud tracks. They're kept in your Keychain.")
                .font(VPFont.body).lineSpacing(3).foregroundStyle(Palette.fgMuted)
                .fixedSize(horizontal: false, vertical: true)
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    keyHeader("OpenRouter", "Clean dictation, Quick answer, cloud voices")
                    KeyField(hint: app.openRouterKeyHint, placeholder: "Paste your OpenRouter key (sk-or-…)",
                             failed: app.openRouterKeyState == .rejected, focusKey: "openrouter-key") { app.setOpenRouterKey($0) }
                    Link("Get a key at openrouter.ai →", destination: URL(string: "https://openrouter.ai/keys")!)
                        .font(.system(size: 12, design: .monospaced)).foregroundStyle(Palette.purple)
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
                Hairline()
                VStack(alignment: .leading, spacing: 8) {
                    keyHeader("TypeSafe · Jev", "picks the model in Route steps; judges trained words")
                    KeyField(hint: app.jevKeyHint, placeholder: "Paste your TypeSafe key", failed: false, focusKey: "typesafe-key") { app.setJevKey($0) }
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
            }
        case .agents:
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Command line and agents").font(VPFont.display)
                Text("optional").font(.system(size: 12, design: .monospaced)).foregroundStyle(Palette.fgMuted)
            }
            Text("Install vp to run your tracks from Terminal, and the skill so coding agents (Claude Code, Codex and others) can speak to you, ask you things out loud and edit your config.")
                .font(VPFont.body).lineSpacing(3).foregroundStyle(Palette.fgMuted)
                .fixedSize(horizontal: false, vertical: true)
            Card { CommandLineCard() }
        case .tryIt:
            Text("Try it").font(VPFont.display)
            HStack(spacing: 6) {
                Text("Click in the box, hold")
                if let hotkey { Keycap(text: hotkey) } else { Text("a hotkey") }
                Text("say something, and let go.")
            }
            .font(VPFont.body).foregroundStyle(Palette.fgMuted)
            VPTextField("Your words land here", text: $tryText, axis: .vertical, font: .system(size: 14, design: .monospaced), minHeight: 64)
            if let run = tryRun {
                HStack(spacing: 8) {
                    HUDTag(state: .done, label: "OK", detail: run.totalMs.msLabel)
                    Text(run.steps.map { "\($0.title) \($0.ms.msLabel)" }.joined(separator: " · "))
                        .font(.system(size: 12, design: .monospaced)).foregroundStyle(Palette.fgMuted).lineLimit(1)
                }
                HStack(spacing: 18) {
                    Wrangler(pose: .done, scale: 2)
                    VStack(alignment: .leading, spacing: 6) {
                        PixelHeadline("saddled up", size: 20)
                        Text("That's the whole loop. Your tracks and their hotkeys live in the menu bar; the Wrangler swings his lasso up there while you're recording.")
                            .font(VPFont.body).lineSpacing(3).foregroundStyle(Palette.fgMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(Palette.bg200))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.green, lineWidth: 1))
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            switch step {
            case .welcome:
                Text("About two minutes. You can change everything later in Setup.")
                    .font(.system(size: 12, design: .monospaced)).foregroundStyle(Palette.comment)
                Spacer()
                Button { finish() } label: { Text("Skip for now").foregroundStyle(Palette.fgMuted) }.buttonStyle(.vpGhost)
                Button("Get started") { go(+1) }.buttonStyle(.vpPrimary).keyboardShortcut(.defaultAction)
            case .permissions:
                back
                Spacer()
                Button { go(+1) } label: { Text("Skip").foregroundStyle(Palette.fgMuted) }.buttonStyle(.vpGhost)
                Button("Continue") { go(+1) }.buttonStyle(.vpPrimary).keyboardShortcut(.defaultAction)
                    .disabled(!(mic == .authorized && trusted))
            case .models:
                back
                Spacer()
                Button("Continue") { go(+1) }.buttonStyle(.vpPrimary).keyboardShortcut(.defaultAction)
            case .keys:
                back
                Spacer()
                Button { go(+1) } label: { Text("Skip, stay local").foregroundStyle(Palette.fgMuted) }.buttonStyle(.vpGhost)
                Button("Continue") { go(+1) }.buttonStyle(.vpPrimary).keyboardShortcut(.defaultAction)
            case .agents:
                back
                Spacer()
                Button { go(+1) } label: { Text("Skip").foregroundStyle(Palette.fgMuted) }.buttonStyle(.vpGhost)
                Button("Continue") { go(+1) }.buttonStyle(.vpSecondary).keyboardShortcut(.defaultAction)
            case .tryIt:
                back
                Spacer()
                Button("Done") {
                    Onboarding.markDone()
                    finish()
                }
                .buttonStyle(.vpPrimary).keyboardShortcut(.defaultAction)
            }
        }
    }

    private var back: some View {
        Button { go(-1) } label: { Text("Back").foregroundStyle(Palette.fgMuted) }.buttonStyle(.vpGhost)
    }

    private func go(_ delta: Int) { step = Step(rawValue: step.rawValue + delta) ?? step }

    // MARK: Pieces

    private func heading(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(VPFont.display)
            Text(detail).font(VPFont.body).lineSpacing(3).foregroundStyle(Palette.fgMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A permission: OK once granted; NEXT (apricot) on the one to do now, with its Allow… as the primary action.
    private func permissionRow(name: String, detail: String, granted: Bool, next: Bool, action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(granted ? "OK" : "NEXT").font(VPFont.label).tracking(0.9)
                .foregroundStyle(granted ? Palette.green : next ? Palette.orange : Palette.fgMuted)
                .frame(width: 44, alignment: .leading).padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(VPFont.bodyStrong)
                Text(detail).font(.system(size: 12, design: .monospaced)).lineSpacing(2).foregroundStyle(Palette.fgMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if granted {
                Text("✓ Allowed").font(.system(size: 12, design: .monospaced)).foregroundStyle(Palette.green)
            } else {
                Button("Allow…", action: action).buttonStyle(next ? VPButtonStyle(kind: .primary) : VPButtonStyle(kind: .secondary))
            }
        }
        .padding(16)
    }

    private var waiting: String? {
        mic != .authorized ? "the microphone" : !trusted ? "Accessibility" : nil
    }

    private var parakeetRow: some View {
        let (code, color, trailing): (String, Color, String) = switch app.parakeetState {
        case .ready: ("OK", Palette.green, "✓ Loaded")
        case .failed: ("FAIL", Palette.red, "failed: retry from Setup")
        case .loading: ("PROC", Palette.yellow, app.parakeetProgress.map { "\(Int($0 * 460)) / 460 MB" } ?? "loading…")
        case .notLoaded: ("INFO", Palette.cyan, "waiting")
        }
        return HStack(spacing: 14) {
            Text(code).font(VPFont.label).tracking(0.9).foregroundStyle(color).frame(width: 44, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("Parakeet v3").font(VPFont.bodyStrong)
                    Text("transcription · needed for Fast dictation").font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Palette.fgMuted).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(trailing).font(.system(size: 12, design: .monospaced)).monospacedDigit()
                        .foregroundStyle(app.parakeetState == .ready ? Palette.green : Palette.fgMuted)
                }
                if let progress = app.parakeetProgress {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2).fill(Palette.bg300)
                            RoundedRectangle(cornerRadius: 2).fill(Palette.cyan).frame(width: geo.size.width * progress)
                        }
                    }
                    .frame(height: 4)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }

    private func voiceRow(_ engine: LocalVoiceEngine, detail: String, optional: Bool) -> some View {
        let state = voices[engine] ?? .notLoaded
        let (code, color): (String, Color) = switch state {
        case .ready: ("OK", Palette.green)
        case .loading: ("PROC", Palette.yellow)
        case .failed: ("FAIL", Palette.red)
        case .notLoaded: ("INFO", Palette.cyan)
        }
        return HStack(spacing: 14) {
            Text(code).font(VPFont.label).tracking(0.9).foregroundStyle(color).frame(width: 44, alignment: .leading)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(engine.label).font(VPFont.bodyStrong)
                Text(detail).font(.system(size: 12, design: .monospaced)).foregroundStyle(Palette.fgMuted).lineLimit(1)
            }
            Spacer(minLength: 8)
            switch state {
            case .ready:
                Text("✓ Loaded").font(.system(size: 12, design: .monospaced)).foregroundStyle(Palette.green)
            case .loading:
                Text("downloading…").font(.system(size: 12, design: .monospaced)).foregroundStyle(Palette.fgMuted)
            case .failed, .notLoaded:
                if optional || { if case .failed = state { true } else { false } }() {
                    Button(optional ? "Load" : "Retry") { Task { try? await LocalVoices.shared.prepare(engine) } }
                        .buttonStyle(.vpSecondary)
                } else {
                    Text("waiting").font(.system(size: 12, design: .monospaced)).foregroundStyle(Palette.fgMuted)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }

    private func keyHeader(_ name: String, _ purpose: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(name).font(VPFont.bodyStrong)
            Text(purpose).font(.system(size: 12, design: .monospaced)).foregroundStyle(Palette.fgMuted).lineLimit(1)
        }
    }

    /// The first hotkey of the first enabled track that has one.
    private var hotkey: String? {
        app.store.tracks.first { $0.enabled && !$0.triggers.isEmpty }?.triggers.first?.combo.display
    }

    /// A run that finished while this step was open.
    private var tryRun: RunRecord? {
        app.history.first.flatMap { $0.date > tryStarted && $0.failure == nil ? $0 : nil }
    }

    private func refresh() {
        mic = AVCaptureDevice.authorizationStatus(for: .audio)
        trusted = AXIsProcessTrusted()
        voices = app.localVoiceStates
        if trusted, PermissionHelper.shared.kind == .accessibility { PermissionHelper.shared.hide() }
        if mic == .authorized, PermissionHelper.shared.kind == .microphone { PermissionHelper.shared.hide() }
        // Pocket TTS loads at launch only if a track uses it; make sure it's on its way during setup.
        if step == .models, voices[.pocket] == nil || voices[.pocket] == .notLoaded,
           app.store.tracks.contains(where: { $0.steps.contains { if case .localSpeech(.pocket, _, _) = $0.kind { true } else { false } } }) {
            Task { try? await LocalVoices.shared.prepare(.pocket) }
        }
    }

    static func openPrivacy(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// A small floating card beside System Settings: what to do, and the app's icon to drag into the privacy list
/// when Voice Pipes isn't there yet. Hides itself once access is granted.
@MainActor
final class PermissionHelper {
    enum Kind { case accessibility, microphone }
    static let shared = PermissionHelper()
    private var panel: NSPanel?
    private(set) var kind: Kind?

    func show(_ kind: Kind) {
        hide()
        self.kind = kind
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 132),
                            styleMask: [.nonactivatingPanel, .titled, .closable, .fullSizeContentView, .utilityWindow],
                            backing: .buffered, defer: false)
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: PermissionHelperView(kind: kind))
        if let screen = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: screen.maxX - 360, y: screen.minY + 24))
        }
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func hide() {
        panel?.close()
        panel = nil
        kind = nil
    }
}

struct PermissionHelperView: View {
    let kind: PermissionHelper.Kind

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            if kind == .accessibility {
                VStack(spacing: 4) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 48, height: 48)
                    Text("Voice Pipes").font(VPFont.caption).foregroundStyle(Palette.fg)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Palette.bg300))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.pink, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                .onDrag { NSItemProvider(contentsOf: Bundle.main.bundleURL) ?? NSItemProvider() }
                .help("Drag into the Accessibility list")
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(kind == .accessibility ? "Turn on Voice Pipes" : "Turn on Voice Pipes under Microphone")
                    .font(VPFont.bodyStrong)
                Text(kind == .accessibility
                     ? "Switch it on in the Accessibility list. Not there? Drag this icon into the list."
                     : "Switch Voice Pipes on in the Microphone list, then come back.")
                    .font(VPFont.caption).foregroundStyle(Palette.fgMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16).padding(.top, 28).padding(.bottom, 16)
        .frame(width: 340, alignment: .leading)
        .background(Palette.bg200)
        .vpWindow()
    }
}
