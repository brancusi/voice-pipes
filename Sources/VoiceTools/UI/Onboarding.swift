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
    private var window: NSWindow?

    func show(_ app: AppState) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = "Set up Voice Pipes"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: OnboardingView(app: app) { [weak self] in self?.close() })
        window.center()
        self.window = window
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
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
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(app: AppState, step: Step = .welcome, finish: @escaping () -> Void) {
        self.app = app
        self.finish = finish
        _step = State(initialValue: step)
    }

    enum Step: Int, CaseIterable {
        case welcome, permissions, models, keys, tryIt
        var title: String {
            switch self {
            case .welcome: "Welcome"
            case .permissions: "Permissions"
            case .models: "Models"
            case .keys: "Keys"
            case .tryIt: "Try it"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if step == .welcome {
                SundownScene()
            } else {
                stepper.padding(.horizontal, 32).padding(.top, 40)
            }
            VStack(alignment: .leading, spacing: 16) {
                content
                Spacer(minLength: 0)
                footer
            }
            .padding(.horizontal, 32).padding(.top, 24).padding(.bottom, 24)
        }
        .frame(width: SundownScene.size.width, height: 640)
        .background(Palette.bg100)
        .vpWindow()
        .onReceive(tick) { _ in refresh() }
        .onAppear(perform: refresh)
    }

    // MARK: Steps

    @ViewBuilder private var content: some View {
        switch step {
        case .welcome:
            PixelHeadline("howdy, partner", size: 24)
            Text("Voice Pipes runs your voice through pipelines you play with hotkeys: hold a key, talk, and the text lands at your cursor. Setup takes about a minute: two permissions, the on-device models (they download in the background), and API keys if you want cloud steps.")
                .font(VPFont.body).lineSpacing(4).foregroundStyle(Palette.fgMuted)
                .fixedSize(horizontal: false, vertical: true)
        case .permissions:
            heading("Two permissions", "macOS asks for each once. Nothing you say leaves your Mac unless a track sends it somewhere.")
            Card {
                permissionRow(name: "Microphone", detail: "Records your voice while you hold or toggle a hotkey.",
                              granted: mic == .authorized, button: mic == .notDetermined ? "Allow…" : "Open Settings…") {
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
                permissionRow(name: "Accessibility", detail: "Pastes at your cursor and reads the text you select.",
                              granted: trusted, button: "Open Settings…") {
                    TextCapture.promptForAccessibility()
                    Self.openPrivacy("Privacy_Accessibility")
                    PermissionHelper.shared.show(.accessibility)
                }
            }
            Text("Voice Pipes not in the list? Drag it in from the little helper that opens next to Settings, then switch it on.")
                .font(VPFont.caption).foregroundStyle(Palette.fgMuted)
        case .models:
            heading("On-device models", "They download once, in the background, and keep going if you close this window.")
            Card {
                modelRow(name: "Parakeet v3", detail: "transcription · ~460 MB", state: parakeet, progress: app.parakeetProgress)
                Hairline()
                modelRow(name: "Pocket TTS", detail: "read aloud · ~770 MB", state: Self.model(voices[.pocket] ?? .notLoaded), progress: nil)
            }
        case .keys:
            heading("API keys (optional)", "Fast dictation and Read aloud run on your Mac and need no keys. Paste a key to turn on the cloud steps; you can do this later in Setup.")
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    keyHeader("OpenRouter", "Clean dictation's cleanup, cloud transcription, LLM and speech models")
                    KeyField(hint: app.openRouterKeyHint, placeholder: "Paste your OpenRouter key (sk-or-…)",
                             failed: app.openRouterKeyState == .rejected) { app.setOpenRouterKey($0) }
                }
                .padding(14)
                Hairline()
                VStack(alignment: .leading, spacing: 10) {
                    keyHeader("TypeSafe · Jev", "Picks the model in Route steps; judges mishearings when you train a word")
                    KeyField(hint: app.jevKeyHint, placeholder: "Paste your TypeSafe key", failed: false) { app.setJevKey($0) }
                }
                .padding(14)
            }
        case .tryIt:
            heading("Try it", "Click in the box, hold a hotkey, say something, and let go.")
            Card {
                ForEach(Array(hotkeyTracks.enumerated()), id: \.element.id) { index, track in
                    if index > 0 { Hairline() }
                    HStack(spacing: 8) {
                        Rectangle().fill(Palette.track(track.colorHex)).frame(width: 7, height: 7)
                        Text(track.name)
                        Spacer()
                        ForEach(track.triggers) { trigger in
                            Keycap(text: trigger.combo.display, mode: trigger.mode == .hold ? "hold" : "toggle")
                        }
                    }
                    .padding(.horizontal, 12).frame(height: 36)
                }
            }
            VPTextField("Your words land here", text: $tryText, axis: .vertical, minHeight: 72)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if step != .welcome {
                Button("Back") { step = Step(rawValue: step.rawValue - 1) ?? .welcome }.buttonStyle(.vpSecondary)
            }
            Spacer()
            if step == .permissions, !(mic == .authorized && trusted) {
                Text("You can finish this later in Setup.").font(VPFont.caption).foregroundStyle(Palette.fgMuted)
            }
            if step == .tryIt {
                Button("Done") {
                    Onboarding.markDone()
                    finish()
                }
                .buttonStyle(.vpPrimary).keyboardShortcut(.defaultAction)
            } else {
                Button(step == .welcome ? "Get started" : step == .keys && !app.hasOpenRouterKey && !app.hasJevKey ? "Skip" : "Continue") {
                    step = Step(rawValue: step.rawValue + 1) ?? .tryIt
                }
                .buttonStyle(.vpPrimary).keyboardShortcut(.defaultAction)
            }
        }
    }

    /// `Welcome › Permissions › Models › Keys › Try it`: done in sage, the current step in bone, the rest dim.
    private var stepper: some View {
        HStack(spacing: 8) {
            ForEach(Step.allCases, id: \.self) { item in
                if item != .welcome { Text("›").foregroundStyle(Palette.comment) }
                Text(item.title)
                    .font(item == step ? VPFont.bodyStrong : VPFont.body)
                    .foregroundStyle(item == step ? Palette.fg : item.rawValue < step.rawValue ? Palette.green : Palette.comment)
            }
        }
        .font(VPFont.caption)
    }

    // MARK: Pieces

    private func heading(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(VPFont.display)
            Text(detail).font(VPFont.body).lineSpacing(3).foregroundStyle(Palette.fgMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func permissionRow(name: String, detail: String, granted: Bool, button: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            StatusCode(level: granted ? .ok : .warning)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(VPFont.bodyStrong)
                Text(detail).font(VPFont.caption).foregroundStyle(Palette.fgMuted)
            }
            Spacer()
            if granted {
                Text("allowed").font(VPFont.caption).foregroundStyle(Palette.fgMuted)
            } else {
                Button(button, action: action).buttonStyle(.vpSecondary)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    private func modelRow(name: String, detail: String, state: (Check.Level, String), progress: Double?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                StatusCode(level: state.0)
                Text(name).font(VPFont.bodyStrong)
                Text(detail).font(VPFont.caption).foregroundStyle(Palette.fgMuted)
                Spacer()
                Text(progress.map { "\(Int($0 * 100))%" } ?? state.1).font(VPFont.caption).monospacedDigit().foregroundStyle(Palette.fgMuted)
            }
            if let progress {
                ProgressBar(value: progress).padding(.leading, 52)
            } else if state.1.hasPrefix("downloading") {
                ProgressView().progressViewStyle(.linear).tint(Palette.purple).padding(.leading, 52)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    private func keyHeader(_ name: String, _ purpose: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(name).font(VPFont.bodyStrong)
            Text(purpose).font(VPFont.caption).foregroundStyle(Palette.fgMuted).lineLimit(1)
        }
    }

    private var parakeet: (Check.Level, String) {
        switch app.parakeetState {
        case .notLoaded: (.info, "waiting")
        case .loading: (.info, "downloading…")
        case .ready: (.ok, "ready")
        case .failed(let error): (.problem, "failed: \(error)")
        }
    }

    private static func model(_ state: LocalVoices.State) -> (Check.Level, String) {
        switch state {
        case .notLoaded: (.info, "waiting")
        case .loading: (.info, "downloading…")
        case .ready: (.ok, "ready")
        case .failed(let error): (.problem, "failed: \(error)")
        }
    }

    private var hotkeyTracks: [Track] { app.store.tracks.filter { $0.enabled && !$0.triggers.isEmpty } }

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
