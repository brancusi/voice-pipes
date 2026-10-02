import AVFoundation
import AppKit
import ApplicationServices
import Observation

/// What flows between steps at runtime.
enum Payload {
    case none
    case audio([Float])
    case text(String)

    var text: String? {
        if case .text(let t) = self { return t }
        return nil
    }
}

/// Live state of the track currently running, shown in the HUD.
struct ActiveRun {
    enum Phase: Equatable { case recording, processing, speaking, done, failed(String) }

    let trackID: Track.ID
    let trackName: String
    let colorHex: String
    /// A Route step's title is replaced by the route Jev picked, so the HUD and Activity show it.
    var stepTitles: [String]
    var phase: Phase
    var currentStep: Int
    var stepMs: [Int?]
    var liveText = ""
    /// Which model is answering (and, for a Route step, the route Jev picked), shown under the HUD tag.
    var modelInfo: String?
    var level: Float = 0
    var recordingStarted = Date()
    /// When processing began (on release, or at once for tracks without a microphone).
    var processingStarted = Date()
    /// Total processing time, set when the run finishes.
    var totalMs: Int?
    var heldBy: String?
}

@MainActor
@Observable
final class AppState {
    let store: TrackStore
    let speaker = Speaker()
    private(set) var run: ActiveRun? {
        didSet {
            if (run?.phase == .recording) != (oldValue?.phase == .recording) { updateLasso() }
        }
    }
    /// The menu bar Wrangler's lasso frame while recording (stepped at 6 fps; still under Reduce Motion).
    private(set) var lassoFrame = 0
    @ObservationIgnored private var lassoTimer: Timer?
    let historyStore: HistoryStore
    /// Every run's text, newest first, kept on disk.
    var history: [RunRecord] { historyStore.records }
    private(set) var parakeetState: ParakeetService.State = .notLoaded
    private(set) var localVoiceStates: [LocalVoiceEngine: LocalVoices.State] = [:]
    private(set) var unavailableCombos: [KeyCombo] = []
    private(set) var checks: [Check] = []
    private(set) var checking = false
    @ObservationIgnored private var recheckPending = false
    var hasOpenRouterKey = Keychain.get(SecretKey.openRouter) != nil
    /// What the main window shows; the menu bar panel sets it to jump straight to Setup.
    var mainSection: MainSection?
    /// Set while the editor records a new key combo, so existing hotkeys don't fire.
    var hotkeysSuspended = false {
        didSet { registerHotkeys(for: store.tracks) }
    }

    @ObservationIgnored let parakeet = ParakeetService()
    @ObservationIgnored private let hotkeys = HotkeyManager()
    @ObservationIgnored private let recorder = AudioRecorder()
    @ObservationIgnored private var capture: Capture?
    @ObservationIgnored private var cancelHotkey: UInt32?
    @ObservationIgnored private var speakingTrack: Track.ID?
    @ObservationIgnored let hud = HUDController()

    /// An in-progress microphone capture.
    private struct Capture {
        let track: Track
        let mode: Trigger.Mode
        let live: LiveTranscriber?
        let started: Date
    }

    /// `startServices: false` builds the state without hotkeys, the HUD, the microphone or models (for rendering
    /// screens offscreen in a scratch harness).
    init(store: TrackStore? = nil, history: HistoryStore? = nil, startServices: Bool = true) {
        self.store = store ?? TrackStore()
        historyStore = history ?? HistoryStore()
        guard startServices else { return }
        hud.attach(self)
        observeTracks()
        Task { await prepare() }
    }

    #if SNAPSHOTS
    /// Harness only: show a run in a given state.
    func setPreviewRun(_ run: ActiveRun?) { self.run = run }
    func setPreviewChecks(_ checks: [Check]) { self.checks = checks }
    #endif

    private func prepare() async {
        _ = Clipboard.shared
        await LocalVoices.shared.observe { engine, state in
            Task { @MainActor [weak self] in
                self?.localVoiceStates[engine] = state
                self?.refreshChecks()
            }
        }
        // Load on-device voices that enabled tracks use, so the first read-aloud doesn't wait for it.
        let engines = Set(store.tracks.filter(\.enabled).flatMap(\.steps).compactMap { step -> LocalVoiceEngine? in
            if case .localSpeech(let engine, _, _) = step.kind { engine } else { nil }
        })
        for engine in engines { Task { try? await LocalVoices.shared.prepare(engine) } }
        _ = await AVCaptureDevice.requestAccess(for: .audio)
        if !TextCapture.isTrusted { TextCapture.promptForAccessibility() }
        if store.tracks.contains(where: { $0.steps.contains { if case .parakeet = $0.kind { true } else { false } } }) {
            parakeetState = .loading
            refreshChecks()
            await parakeet.load()
            parakeetState = await parakeet.state
        }
        refreshChecks()
    }

    var hasJevKey = JevClient.hasKey
    /// The saved keys as Setup shows them (`sk-or-v1-••••3f9a`): read once, never the whole key.
    private(set) var openRouterKeyHint = AppState.mask(Keychain.get(SecretKey.openRouter))
    private(set) var jevKeyHint = AppState.mask(Keychain.get(SecretKey.typesafe))

    enum KeyState { case checking, valid, rejected, unreachable }
    /// The OpenRouter key's live check, or nil when there's no key or it hasn't been checked yet.
    private(set) var openRouterKeyState: KeyState?

    /// Saves (or, with an empty string, removes) the Jev key.
    func setJevKey(_ key: String) {
        Keychain.set(key.trimmingCharacters(in: .whitespacesAndNewlines), for: SecretKey.typesafe)
        hasJevKey = JevClient.hasKey
        jevKeyHint = Self.mask(Keychain.get(SecretKey.typesafe))
        refreshChecks()
    }

    /// Saves (or, with an empty string, removes) the OpenRouter key, then checks it.
    func setOpenRouterKey(_ key: String) {
        Keychain.set(key.trimmingCharacters(in: .whitespacesAndNewlines), for: SecretKey.openRouter)
        hasOpenRouterKey = Keychain.get(SecretKey.openRouter) != nil
        openRouterKeyHint = Self.mask(Keychain.get(SecretKey.openRouter))
        openRouterKeyState = nil
        checkOpenRouterKey()
        refreshChecks()
    }

    func checkOpenRouterKey() {
        guard hasOpenRouterKey, openRouterKeyState != .checking else { return }
        openRouterKeyState = .checking
        Task {
            openRouterKeyState = switch await OpenRouterClient.shared.validateKey() {
            case .valid: .valid
            case .rejected: .rejected
            case .unreachable: .unreachable
            }
        }
    }

    /// The key's prefix (up to its last `-` or `_` in the first 12 characters, e.g. `sk-or-v1-`), dots, and the
    /// last four characters. Short keys show only dots.
    nonisolated static func mask(_ key: String?) -> String? {
        guard let key = key?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else { return nil }
        let dots = String(repeating: "•", count: 12)
        guard key.count >= 16 else { return dots }
        let head = key.prefix(12)
        let prefix = head.lastIndex(where: { $0 == "-" || $0 == "_" }).map { String(head[...$0]) } ?? ""
        return prefix + dots + String(key.suffix(4))
    }

    // MARK: - Checks

    var worstCheck: Check.Level { checks.map(\.level).max() ?? .ok }

    func refreshChecks() {
        #if SNAPSHOTS
        return
        #endif
        guard !checking else {
            recheckPending = true
            return
        }
        checking = true
        Task {
            checks = await Diagnostics.run(self)
            checking = false
            if recheckPending {
                recheckPending = false
                refreshChecks()
            }
        }
    }

    /// Runs a check's fix, then watches for the permission to arrive so the panel updates by itself.
    func fix(_ fix: Check.Fix) {
        Task {
            await Diagnostics.fix(fix)
            refreshChecks()
            for _ in 0..<90 {
                try? await Task.sleep(for: .seconds(1))
                let granted = switch fix {
                case .accessibilitySettings: AXIsProcessTrusted()
                case .microphoneSettings: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
                case .editTracks: true
                }
                if granted { break }
            }
            refreshChecks()
        }
    }

    func copyReport() {
        Clipboard.shared.copy(Diagnostics.report(checks, tracks: store.tracks))
    }

    // MARK: - Hotkeys

    private func observeTracks() {
        withObservationTracking {
            registerHotkeys(for: store.tracks)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeTracks() }
        }
    }

    private func registerHotkeys(for tracks: [Track]) {
        guard !hotkeysSuspended else {
            hotkeys.unregisterAll()
            return
        }
        var bindings: [(KeyCombo, HotkeyManager.Handler)] = []
        for track in tracks where track.enabled {
            for trigger in track.triggers {
                let id = track.id, mode = trigger.mode, label = trigger.combo.display
                bindings.append((trigger.combo, { [weak self] pressed in
                    self?.handleTrigger(trackID: id, mode: mode, pressed: pressed, label: label)
                }))
            }
        }
        unavailableCombos = hotkeys.register(bindings)
    }

    private func handleTrigger(trackID: Track.ID, mode: Trigger.Mode, pressed: Bool, label: String) {
        guard let track = store.tracks.first(where: { $0.id == trackID }) else { return }

        // A capture for this track is in progress: this press/release may end it.
        if let capture, capture.track.id == trackID {
            let ends = (mode == .hold && !pressed) || (mode == .toggle && pressed)
            if ends { Task { await finishCapture() } }
            return
        }
        guard pressed else { return }

        // Pressing a speaking track's trigger pauses or resumes it.
        if speakingTrack == trackID, speaker.state != .idle {
            // Still fetching the first passage: a second press means "never mind".
            speaker.state == .loading ? speaker.clear() : speaker.togglePause()
            return
        }
        guard capture == nil else { return }
        start(track, mode: mode, label: label)
    }

    private func updateLasso() {
        lassoTimer?.invalidate()
        lassoTimer = nil
        lassoFrame = 0
        guard run?.phase == .recording, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        lassoTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 6, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.lassoFrame += 1 }
        }
    }

    // MARK: - Running tracks

    func start(_ track: Track, mode: Trigger.Mode = .toggle, label: String? = nil) {
        if let error = track.validationError {
            show(failure: error, for: track)
            return
        }
        run = ActiveRun(trackID: track.id, trackName: track.name, colorHex: track.colorHex,
                        stepTitles: track.steps.map(\.kind.title), phase: .processing, currentStep: 0,
                        stepMs: Array(repeating: nil, count: track.steps.count), heldBy: label)

        guard case .microphone = track.steps[0].kind else {
            Task { await runSteps(track, from: 0, payload: .none) }
            return
        }
        beginCapture(track, mode: mode)
    }

    private func beginCapture(_ track: Track, mode: Trigger.Mode) {
        let showPartial: @Sendable (String) -> Void = { [weak self] text in
            Task { @MainActor in self?.run?.liveText = text }
        }
        var live: LiveTranscriber?
        if track.steps.count > 1, case .parakeet(let pauseMs, let parakeetMode) = track.steps[1].kind {
            switch parakeetMode ?? .onRelease {
            case .onRelease:
                break
            case .pauseChunks:
                let transcriber = ChunkedTranscriber(parakeet: parakeet, pauseMs: pauseMs)
                transcriber.onPartial = showPartial
                live = transcriber
            case .streaming:
                live = StreamingTranscriber(parakeet: parakeet, onPartial: showPartial)
            }
        }
        if track.steps.contains(where: \.kind.usesOpenRouter) { OpenRouterClient.shared.prewarm() }

        recorder.onSamples = live.map { transcriber in { @Sendable samples in transcriber.feed(samples) } }
        recorder.onLevel = { [weak self] level in
            Task { @MainActor in self?.run?.level = level }
        }
        do {
            try recorder.start()
        } catch {
            show(failure: "Microphone unavailable: \(error.localizedDescription)", for: track)
            return
        }
        capture = Capture(track: track, mode: mode, live: live, started: Date())
        run?.phase = .recording
        run?.recordingStarted = Date()
        cancelHotkey = hotkeys.add(KeyCombo(key: .escape, modifiers: []), { [weak self] pressed in
            if pressed { self?.cancelCapture() }
        })
    }

    func cancelCapture() {
        guard let live = capture.map({ $0.live }) else { return }
        _ = recorder.stop()
        live?.cancel()
        endCaptureHotkeys()
        capture = nil
        run = nil
    }

    private func endCaptureHotkeys() {
        if let cancelHotkey { hotkeys.remove(cancelHotkey) }
        cancelHotkey = nil
    }

    private func finishCapture() async {
        guard let capture else { return }
        self.capture = nil
        endCaptureHotkeys()
        let samples = recorder.stop()
        run?.phase = .processing
        run?.processingStarted = Date()
        run?.stepMs[0] = Int(Date().timeIntervalSince(capture.started) * 1000)

        // Ignore accidental taps.
        guard samples.count > Int(AudioRecorder.sampleRate * 0.25) else {
            run = nil
            return
        }

        if let live = capture.live {
            run?.currentStep = 1
            let released = Date()
            var text = (try? await live.finish()) ?? ""
            if text.isEmpty {
                // Live transcription failed or found nothing: fall back to the whole recording.
                NSLog("VoiceTools: live transcription returned nothing; transcribing the whole recording")
                text = (try? await parakeet.transcribe(samples)) ?? ""
            }
            run?.stepMs[1] = Int(Date().timeIntervalSince(released) * 1000)
            await runSteps(capture.track, from: 2, payload: .text(text), startedAt: released)
        } else {
            await runSteps(capture.track, from: 1, payload: .audio(samples))
        }
    }

    private func runSteps(_ track: Track, from start: Int, payload initial: Payload, startedAt: Date = Date()) async {
        var payload = initial
        var index = start
        var heard: String?
        while index < track.steps.count {
            let step = track.steps[index]
            run?.currentStep = index
            let t0 = Date()
            do {
                payload = try await execute(step.kind, payload: payload, track: track)
            } catch {
                if case .llm(_, _, .passThrough) = step.kind {
                    NSLog("VoiceTools: \(step.kind.title) failed, passing input through: \(error)")
                } else {
                    // Keep what the run had so far, so a dictation whose paste failed can still be copied.
                    record(track, startedAt: startedAt, heard: heard, failure: error.localizedDescription)
                    show(failure: error.localizedDescription, for: track)
                    return
                }
            }
            run?.stepMs[index] = Int(Date().timeIntervalSince(t0) * 1000)
            if let text = payload.text {
                run?.liveText = text
                if step.kind.category == "Transcribe" { heard = text }
            }
            index += 1
        }

        let total = record(track, startedAt: startedAt, heard: heard, failure: nil)
        run?.totalMs = total
        run?.phase = .done
        try? await Task.sleep(for: .milliseconds(650))
        if run?.phase == .done, run?.trackID == track.id { run = nil }
    }

    /// Adds the run's text (if any) to History; returns the total time.
    @discardableResult
    private func record(_ track: Track, startedAt: Date, heard: String?, failure: String?) -> Int {
        let total = Int(Date().timeIntervalSince(startedAt) * 1000)
        guard let text = run?.liveText, !text.isEmpty, run?.trackID == track.id else { return total }
        let steps = zip(run?.stepTitles ?? [], run?.stepMs ?? []).enumerated().compactMap { index, pair -> RunRecord.StepTiming? in
            // The microphone's time is how long you spoke, not processing.
            guard let ms = pair.1, !(index == 0 && track.steps.first?.kind == .microphone) else { return nil }
            return RunRecord.StepTiming(title: pair.0, ms: ms, category: track.steps[safe: index]?.kind.category)
        }
        historyStore.add(RunRecord(trackName: track.name, colorHex: track.colorHex, date: Date(), text: text, totalMs: total, steps: steps,
                                   heard: heard == text ? nil : heard, failure: failure))
        return total
    }

    private func execute(_ kind: StepKind, payload: Payload, track: Track) async throws -> Payload {
        switch kind {
        case .microphone:
            throw PipelineError.misplacedInput

        case .text(let sources):
            for source in sources {
                if let text = await TextCapture.read(source) { return .text(text) }
            }
            throw PipelineError.noText

        case .parakeet:
            guard case .audio(let samples) = payload else { throw PipelineError.expected(.audio) }
            return .text(try await parakeet.transcribe(samples))

        case .openRouterSTT(let model):
            guard case .audio(let samples) = payload else { throw PipelineError.expected(.audio) }
            return .text(try await OpenRouterClient.shared.transcribe(wav: WAV.encode(samples), model: model))

        case .llm(let model, let prompt, _):
            if run?.trackID == track.id { run?.modelInfo = String(model.split(separator: "/").last ?? "") }
            return .text(try await complete(model: model, prompt: prompt, input: try text(of: payload)))

        case .route(let routes):
            let input = try text(of: payload)
            guard !routes.isEmpty else { throw PipelineError.noRoutes }
            let t0 = Date()
            let chosen: Int
            let label: String
            var jevMs: Int?
            var confidence = 0.0
            do {
                let pick = try await JevClient.shared.chooseRoute(input: input, routes: routes)
                chosen = pick.index
                jevMs = Int(Date().timeIntervalSince(t0) * 1000)
                confidence = pick.probability
                label = "Jev \(jevMs!) ms → \(routes[chosen].name) \(Int(pick.probability * 100))%"
            } catch {
                // Without Jev the first route still answers, so the track keeps working.
                NSLog("VoiceTools: Jev routing failed, using the first route: \(error)")
                chosen = 0
                label = "Jev failed → \(routes[0].name)"
            }
            let route = routes[chosen]
            let model = route.model.split(separator: "/").last ?? ""
            if let index = run?.currentStep, run?.trackID == track.id {
                run?.stepTitles[index] = "\(label) · \(model)"
                run?.modelInfo = "\(route.name) → \(model) · " + (jevMs.map { "Jev \($0) ms \(Int(confidence * 100))%" } ?? "Jev failed")
            }
            return .text(try await complete(model: route.model, prompt: route.prompt, input: input))

        case .http(let url, let method, let headers, let body, let field):
            return .text(try await HTTPStep.run(input: try text(of: payload), url: url, method: method,
                                                headers: headers, bodyTemplate: body, responseField: field))

        case .template(let template):
            return .text(Template.render(template, input: try text(of: payload)))

        case .fixWords:
            return .text(FixWords.apply(try text(of: payload), entries: VocabularyStore.shared.entries))

        case .paste(let restore):
            let input = try text(of: payload)
            do {
                try await Clipboard.shared.paste(input, restore: restore)
            } catch {
                refreshChecks()
                throw error
            }
            return payload

        case .copy:
            Clipboard.shared.copy(try text(of: payload))
            return payload

        case .speak(let voiceID, let rate):
            let input = try text(of: payload)
            speakingTrack = track.id
            run?.phase = .speaking
            await speaker.speakSystem(input, voiceID: voiceID, rate: rate, label: track.name)
            speakingTrack = nil
            return .none

        case .localSpeech(let engine, let voice, let rate):
            let input = try text(of: payload)
            speakingTrack = track.id
            run?.phase = .speaking
            defer { speakingTrack = nil }
            try await speaker.speakLocal(input, engine: engine, voice: voice, rate: rate, label: track.name)
            return .none

        case .openRouterSpeech(let model, let voice, let rate):
            let input = try text(of: payload)
            speakingTrack = track.id
            run?.phase = .speaking
            defer { speakingTrack = nil }
            try await speaker.speakCloud(input, model: model, voice: voice, rate: rate, label: track.name)
            return .none

        case .showHUD:
            run?.liveText = try text(of: payload)
            try? await Task.sleep(for: .seconds(3))
            return payload
        }
    }

    /// An LLM call as the LLM step makes it: the shared vocabulary rides along as a glossary, so the model keeps
    /// your spellings; `{{input}}` in the prompt places the text, otherwise it's sent as the user message.
    private func complete(model: String, prompt: String, input: String) async throws -> String {
        let glossary = VocabularyStore.shared.glossary
        let instructions = glossary.isEmpty ? prompt
            : prompt + "\n\nGlossary (always use these exact spellings): " + glossary.joined(separator: ", ") + "."
        if prompt.contains("{{input") {
            return try await OpenRouterClient.shared.complete(model: model, system: nil, user: Template.render(instructions, input: input))
        }
        return try await OpenRouterClient.shared.complete(model: model, system: instructions, user: input)
    }

    private func text(of payload: Payload) throws -> String {
        guard let text = payload.text else { throw PipelineError.expected(.text) }
        return text
    }

    private func show(failure message: String, for track: Track) {
        if run == nil || run?.trackID != track.id {
            run = ActiveRun(trackID: track.id, trackName: track.name, colorHex: track.colorHex,
                            stepTitles: track.steps.map(\.kind.title), phase: .processing, currentStep: 0,
                            stepMs: Array(repeating: nil, count: track.steps.count))
        }
        run?.phase = .failed(message)
        Task {
            try? await Task.sleep(for: .seconds(4))
            if case .failed = self.run?.phase { self.run = nil }
        }
    }
}

enum PipelineError: LocalizedError {
    case misplacedInput
    case noText
    case expected(DataKind)
    case noRoutes

    var errorDescription: String? {
        switch self {
        case .misplacedInput: "Microphone can only be the first step."
        case .noText: "No text found (nothing selected and clipboard empty)."
        case .expected(let kind): "This step expected \(kind.rawValue) input."
        case .noRoutes: "Route · Jev needs at least one route."
        }
    }
}

extension StepKind {
    var usesOpenRouter: Bool {
        switch self {
        case .openRouterSTT, .llm, .route, .openRouterSpeech: true
        default: false
        }
    }
}
