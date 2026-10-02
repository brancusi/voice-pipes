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
    /// Branch blocks (by step index): Jev's time, and the chosen branch's steps with their times, for History.
    var branchDetail: [Int: (jevMs: Int, steps: [RunRecord.StepTiming])] = [:]
    /// The run's log so far, saved with it in History.
    var log: [RunRecord.LogEntry] = []
}

@MainActor
@Observable
final class AppState {
    let store: TrackStore
    let speaker = Speaker()
    var run: ActiveRun? {
        didSet {
            if run?.phase != oldValue?.phase, let run, let event = Self.phaseEvent(run.phase) {
                // The track's id when it's a configured track, so events match `vp tracks` and `vp run`.
                emit(["event": event, "track": store.tracks.first { $0.id == run.trackID }?.slug ?? run.trackName])
            }
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
    /// The HUD's read-along card is open; remembered, so the next read-aloud opens the same way.
    var readAlong = UserDefaults.standard.bool(forKey: "hud.readAlong") {
        didSet { UserDefaults.standard.set(readAlong, forKey: "hud.readAlong") }
    }
    /// Set while the editor records a new key combo, so existing hotkeys don't fire.
    var hotkeysSuspended = false {
        didSet { registerHotkeys(for: store.tracks) }
    }

    @ObservationIgnored let parakeet = ParakeetService()
    @ObservationIgnored private let hotkeys = HotkeyManager()
    @ObservationIgnored let recorder = AudioRecorder()
    @ObservationIgnored var capture: Capture?
    @ObservationIgnored private var cancelHotkey: UInt32?
    @ObservationIgnored private var speakingTrack: Track.ID?
    @ObservationIgnored let hud = HUDController()

    /// An in-progress microphone capture.
    struct Capture {
        let track: Track
        let mode: Trigger.Mode
        let live: LiveTranscriber?
        let started: Date
    }

    /// `startServices: false` builds the state without hotkeys, the HUD, the microphone or models (for rendering
    /// screens offscreen in a scratch harness).
    /// Parakeet's first download, 0…1 (nil when it isn't downloading).
    /// Show the setup window: a first launch, or a permission is missing and setup was never finished.
    let needsOnboarding: Bool

    /// Only for this track's run, and only in range: another run may have replaced it meanwhile.
    private func setStepMs(_ index: Int, _ ms: Int, for track: Track) {
        guard run?.trackID == track.id, index < (run?.stepMs.count ?? 0) else { return }
        run?.stepMs[index] = ms
    }

    /// A vp recording starts: it owns the microphone; Esc (and `vp stop`) cancel it.
    func beginAgentRecording() {
        agentRecording = true
        agentCancelled = false
        cancelHotkey = hotkeys.add(KeyCombo(key: .escape, modifiers: []), { [weak self] pressed in
            if pressed { self?.agentCancelled = true }
        })
    }

    func endAgentRecording() {
        agentRecording = false
        if let cancelHotkey { hotkeys.remove(cancelHotkey) }
        cancelHotkey = nil
    }

    @ObservationIgnored private var registeredSignature: [String]?
    /// True while `vp listen` / `vp ask` / a vp microphone run records; hotkeys wait, `vp stop` and Esc cancel it.
    @ObservationIgnored var agentRecording = false
    @ObservationIgnored var agentCancelled = false

    /// `vp watch` connections, sent every run event.
    @ObservationIgnored var watchers: [ControlReply] = []
    /// A word `vp vocab train` asked to train; the Vocabulary page opens its training sheet.
    var pendingTraining: String?
    @ObservationIgnored private var control: ControlServer?

    func emit(_ event: [String: Any]) {
        watchers.removeAll { !$0.isOpen }
        var event = event
        event["at"] = ISO8601DateFormatter().string(from: Date())
        for watcher in watchers { watcher.event(event) }
    }

    private static func phaseEvent(_ phase: ActiveRun.Phase) -> String? {
        switch phase {
        case .recording: "run.recording"
        case .processing: "run.processing"
        case .speaking: "run.speaking"
        case .done, .failed: nil  // sent with their details from runSteps
        }
    }

    init(store: TrackStore? = nil, history: HistoryStore? = nil, startServices: Bool = true) {
        self.store = store ?? TrackStore()
        historyStore = history ?? HistoryStore()
        needsOnboarding = startServices && Onboarding.shouldShow(freshInstall: self.store.createdFresh)
        guard startServices else { return }
        self.store.onIssuesChanged = { [weak self] in self?.refreshChecks() }
        VocabularyStore.shared.onIssuesChanged = { [weak self] in self?.refreshChecks() }
        self.store.onExternalChanges = { [weak self] in self?.showExternalChanges($0) }
        hud.attach(self)
        observeTracks()
        // `vp` talks to the app through this socket.
        let server = ControlServer { [weak self] cmd, args, reply in
            guard let self else { return reply.error("not_ready", "Voice Pipes is starting.") }
            self.handleControl(cmd, args, reply)
        }
        server.start()
        control = server
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
        let engines = Set(store.tracks.filter(\.enabled).flatMap(\.allSteps).compactMap { step -> LocalVoiceEngine? in
            if case .localSpeech(let engine, _, _) = step.kind { engine } else { nil }
        })
        for engine in engines { Task { try? await LocalVoices.shared.prepare(engine) } }
        // The setup window asks for permissions itself, with an explanation; otherwise ask straight away.
        if !needsOnboarding {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
            if !TextCapture.isTrusted { TextCapture.promptForAccessibility() }
        }
        if store.tracks.contains(where: { $0.allSteps.contains { if case .parakeet = $0.kind { true } else { false } } }) {
            parakeetState = .loading
            refreshChecks()
            ModelDownloads.shared.track(.parakeet)
            await parakeet.load()
            ModelDownloads.shared.finish(.parakeet)
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
                case .editTracks, .openConfig, .relinkCLI: true
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
            registeredSignature = nil
            return
        }
        // A config reload re-assigns the tracks even when nothing about hotkeys changed; re-registering then would
        // drop a recording's Esc and a held key's release, so skip it.
        let signature = tracks.filter(\.enabled).flatMap { track in track.triggers.map { "\(track.id)|\($0.combo.key.code)|\($0.combo.modifiers.rawValue)|\($0.mode)" } }
        guard signature != registeredSignature else { return }
        registeredSignature = signature
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
        // register() replaced every hotkey, including a reading's shortcuts and a recording's Esc.
        if readingShortcutsOn { setReadingShortcuts(true) }
        if capture != nil || agentRecording {
            cancelHotkey = hotkeys.add(KeyCombo(key: .escape, modifiers: []), { [weak self] pressed in
                if pressed { self?.cancelCapture() }
            })
        }
    }

    private func handleTrigger(trackID: Track.ID, mode: Trigger.Mode, pressed: Bool, label: String) {
        guard let track = store.tracks.first(where: { $0.id == trackID }) else { return }

        // A capture for this track is in progress: this press/release may end it.
        if let capture, capture.track.id == trackID {
            let ends = (mode == .hold && !pressed) || (mode == .toggle && pressed)
            if ends { Task { await finishCapture() } }
            return
        }
        // `vp listen` / a vp-started run owns the microphone and the HUD until it's done.
        if agentRecording { return }
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
        if track.allSteps.contains(where: \.kind.usesOpenRouter) { OpenRouterClient.shared.prewarm() }

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
        if agentRecording { agentCancelled = true }
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
        setStepMs(0, Int(Date().timeIntervalSince(capture.started) * 1000), for: capture.track)

        // Ignore accidental taps.
        guard samples.count > Int(AudioRecorder.sampleRate * 0.25) else {
            run = nil
            return
        }

        if let live = capture.live {
            if run?.trackID == capture.track.id { run?.currentStep = 1 }
            let released = Date()
            var text = (try? await live.finish()) ?? ""
            if text.isEmpty {
                // Live transcription failed or found nothing: fall back to the whole recording.
                NSLog("VoiceTools: live transcription returned nothing; transcribing the whole recording")
                text = (try? await parakeet.transcribe(samples)) ?? ""
            }
            setStepMs(1, Int(Date().timeIntervalSince(released) * 1000), for: capture.track)
            await runSteps(capture.track, from: 2, payload: .text(text), startedAt: released)
        } else {
            await runSteps(capture.track, from: 1, payload: .audio(samples))
        }
    }

    /// How a run ended: its final text (what was pasted, spoken or sent), or why it stopped.
    struct RunOutcome {
        var text: String?
        var totalMs: Int
        var failure: String?
    }

    @discardableResult
    func runSteps(_ track: Track, from start: Int, payload initial: Payload, startedAt: Date = Date()) async -> RunOutcome {
        var payload = initial
        var index = start
        var heard: String?
        if run?.trackID == track.id { run?.log = prelude(track, from: start, payload: initial) }
        while index < track.steps.count {
            let step = track.steps[index]
            if run?.trackID == track.id { run?.currentStep = index }
            let t0 = Date()
            do {
                payload = try await runLogged(step, payload: payload, track: track, depth: 0, index: index)
            } catch {
                // Keep what the run had so far, so a dictation whose paste failed can still be copied.
                let total = record(track, startedAt: startedAt, heard: heard, failure: error.localizedDescription)
                show(failure: error.localizedDescription, for: track)
                emit(["event": "run.failed", "track": track.slug ?? track.name, "error": error.localizedDescription])
                return RunOutcome(text: run?.liveText, totalMs: total, failure: error.localizedDescription)
            }
            // A Branch's own time is Jev's; the steps it ran are listed after it with theirs.
            let jevMs = run?.trackID == track.id ? run?.branchDetail[index]?.jevMs : nil
            setStepMs(index, jevMs ?? Int(Date().timeIntervalSince(t0) * 1000), for: track)
            if let text = payload.text {
                run?.liveText = text
                if step.kind.category == "Transcribe" { heard = text }
            }
            index += 1
        }

        let total = record(track, startedAt: startedAt, heard: heard, failure: nil)
        let finalText = run?.liveText
        run?.totalMs = total
        run?.phase = .done
        emit(["event": "run.done", "track": track.slug ?? track.name, "ms": total, "text": finalText ?? ""])
        Task {
            try? await Task.sleep(for: .milliseconds(650))
            if run?.phase == .done, run?.trackID == track.id { run = nil }
        }
        return RunOutcome(text: finalText, totalMs: total, failure: nil)
    }

    // MARK: The run log

    /// One step, logged: text in and out, time, what its cloud calls used, and (Route) Jev's pick. A Branch logs
    /// itself and its steps. An LLM set to pass through on failure hands its input on (logged as such); any other
    /// failure is logged and rethrown.
    private func runLogged(_ step: Step, payload: Payload, track: Track, depth: Int, index: Int?) async throws -> Payload {
        if case .branch = step.kind { return try await execute(step.kind, payload: payload, track: track, depth: depth) }
        let meter = UsageMeter()
        let t0 = Date()
        lastDecision = nil
        // Cloud transcription's title is the bare model id; say what the step is.
        var entry = RunRecord.LogEntry(title: Self.logTitle(step.kind), category: step.kind.category, depth: depth, ms: 0,
                                       input: Self.describe(payload), status: .ok, voice: Self.logVoice(step.kind))
        func finish(_ output: Payload?) {
            entry.ms = Int(Date().timeIntervalSince(t0) * 1000)
            if let index, depth == 0, case .route = step.kind, let title = run?.stepTitles[safe: index], run?.trackID == track.id { entry.title = title }
            entry.output = output.flatMap(Self.describe)
            entry.usage = meter.total ?? (Self.runsOnThisMac(step.kind) ? RunRecord.Usage(local: true) : nil)
            entry.decision = lastDecision
            if run?.trackID == track.id { run?.log.append(entry) }
        }
        do {
            let output = try await UsageMeter.$current.withValue(meter) {
                try await execute(step.kind, payload: payload, track: track, depth: depth)
            }
            finish(output)
            return output
        } catch {
            entry.message = error.localizedDescription
            if case .llm(_, _, .passThrough) = step.kind {
                NSLog("VoiceTools: \(step.kind.title) failed, passing input through: \(error)")
                entry.status = .passedThrough
                finish(payload)
                return payload
            }
            entry.status = .failed
            finish(nil)
            throw error
        }
    }

    /// A step's name in the log: what it is and which model, without words the usage column already says
    /// ("on this Mac") and without the voice (it goes with the usage, so it isn't cut off at narrow widths).
    static func logTitle(_ kind: StepKind) -> String {
        switch kind {
        case .openRouterSTT(let model): "Transcribe · \(model.split(separator: "/").last ?? "")"
        case .parakeet(_, let mode): (mode ?? .onRelease) == .onRelease ? "Parakeet v3" : kind.title.replacingOccurrences(of: " · local", with: "")
        case .localSpeech(let engine, _, _): "Speak · \(engine.label)"
        case .openRouterSpeech(let model, _, _): "Speak · \(model.split(separator: "/").last ?? "")"
        case .speak: "Speak · macOS voice"
        default: kind.title
        }
    }

    static func logVoice(_ kind: StepKind) -> String? {
        switch kind {
        case .localSpeech(let engine, let voice, _): engine.voiceLabel(voice)
        case .openRouterSpeech(_, let voice, _): OpenRouterCatalog.Model.voiceLabel(voice).components(separatedBy: " (").first
        case .speak(let id, _): id.flatMap { AVSpeechSynthesisVoice(identifier: $0)?.name }
        default: nil
        }
    }

    // MARK: Steering a reading

    /// One reading action, from the HUD's keys, a global shortcut or `vp next` / `vp prev` / `vp speed`.
    func readingAction(_ action: ReadingSettings.Action) {
        switch action {
        case .stop: speaker.clear()
        case .pause: speaker.togglePause()
        case .next: speaker.seek(toSentence: min(speaker.currentSentence + 1, max(0, speaker.sentences.count - 1)))
        case .previous: speaker.seek(toSentence: max(0, speaker.currentSentence - 1))
        case .slower: speaker.setRate(speaker.rate - 0.1)
        case .faster: speaker.setRate(speaker.rate + 0.1)
        case .start: speaker.seek(toSentence: 0)
        case .end: speaker.seek(toSentence: max(0, speaker.sentences.count - 1))
        }
    }

    @ObservationIgnored private var readingShortcutIDs: [UInt32] = []
    @ObservationIgnored private var readingShortcutsOn = false

    /// [settings.reading.global]: registered only while something is being read.
    func setReadingShortcuts(_ on: Bool) {
        readingShortcutsOn = on
        readingShortcutIDs.forEach { hotkeys.remove($0) }
        readingShortcutIDs = []
        guard on else { return }
        for (action, combo) in store.reading.global {
            if let id = hotkeys.add(combo, { [weak self] pressed in if pressed { self?.readingAction(action) } }) {
                readingShortcutIDs.append(id)
            }
        }
    }

    /// A Route's pick, for its log entry (set while it runs).
    @ObservationIgnored private var lastDecision: RunRecord.Decision?

    /// Steps that ran before `runSteps` (the recording; streamed transcription; text handed over by `vp run`).
    private func prelude(_ track: Track, from start: Int, payload: Payload) -> [RunRecord.LogEntry] {
        guard start > 0 else { return [] }
        var entries: [RunRecord.LogEntry] = []
        let recorded = run.map { $0.processingStarted.timeIntervalSince($0.recordingStarted) } ?? 0
        if track.steps.first?.kind == .microphone {
            entries.append(RunRecord.LogEntry(title: "Microphone", category: "Input", depth: 0, ms: Int(max(0, recorded) * 1000),
                                              output: String(format: "audio · %.1f s", max(0, recorded)), usage: RunRecord.Usage(local: true),
                                              status: .ok, message: "recorded while the hotkey was held or toggled"))
            if start >= 2, let transcribe = track.steps[safe: 1] {
                entries.append(RunRecord.LogEntry(title: transcribe.kind.title, category: transcribe.kind.category, depth: 0, ms: 0,
                                                  input: String(format: "audio · %.1f s", max(0, recorded)), output: Self.describe(payload),
                                                  usage: RunRecord.Usage(local: true), status: .ok, message: "transcribed while you spoke"))
            }
        } else if payload.text != nil {
            entries.append(RunRecord.LogEntry(title: "Text from vp", category: "Input", depth: 0, ms: 0, output: Self.describe(payload),
                                              status: .ok, message: "handed over by `vp run`, so the track's earlier steps were skipped"))
        }
        return entries
    }

    /// A payload for the log: text (capped), "audio · 4.2 s", or nothing.
    static func describe(_ payload: Payload) -> String? {
        switch payload {
        case .text(let text): text.count > 2000 ? String(text.prefix(2000)) + "…" : text
        case .audio(let samples): String(format: "audio · %.1f s", Double(samples.count) / 16_000)
        case .none: nil
        }
    }

    /// Runs on this Mac with no cloud call (logged as "on this Mac").
    static func runsOnThisMac(_ kind: StepKind) -> Bool {
        switch kind {
        case .microphone, .text, .parakeet, .fixWords, .template, .paste, .copy, .speak, .localSpeech, .showHUD: true
        case .openRouterSTT, .llm, .route, .branch, .http, .openRouterSpeech: false
        }
    }

    /// Adds the run's text (if any) to History; returns the total time.
    @discardableResult
    private func record(_ track: Track, startedAt: Date, heard: String?, failure: String?) -> Int {
        let total = Int(Date().timeIntervalSince(startedAt) * 1000)
        guard let text = run?.liveText, !text.isEmpty, run?.trackID == track.id else { return total }
        let steps = zip(run?.stepTitles ?? [], run?.stepMs ?? []).enumerated().flatMap { index, pair -> [RunRecord.StepTiming] in
            // The microphone's time is how long you spoke, not processing.
            guard let ms = pair.1, !(index == 0 && track.steps.first?.kind == .microphone) else { return [] }
            return [RunRecord.StepTiming(title: pair.0, ms: ms, category: track.steps[safe: index]?.kind.category)]
                + (run?.branchDetail[index]?.steps ?? [])
        }
        historyStore.add(RunRecord(trackName: track.name, colorHex: track.colorHex, date: Date(), text: text, totalMs: total, steps: steps,
                                   heard: heard == text ? nil : heard, failure: failure, log: run?.log))
        return total
    }

    private func execute(_ kind: StepKind, payload: Payload, track: Track, depth: Int = 0) async throws -> Payload {
        let nested = depth > 0
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
            lastDecision = RunRecord.Decision(kind: "route", question: nil, chosen: route.name, confidence: jevMs == nil ? nil : confidence,
                                              jevMs: jevMs ?? Int(Date().timeIntervalSince(t0) * 1000),
                                              others: routes.indices.filter { $0 != chosen }.map { routes[$0].name })
            let model = route.model.split(separator: "/").last ?? ""
            if let index = run?.currentStep, run?.trackID == track.id, index < (run?.stepTitles.count ?? 0) {
                run?.stepTitles[index] = "\(label) · \(model)"
                run?.modelInfo = "\(route.name) → \(model) · " + (jevMs.map { "Jev \($0) ms \(Int(confidence * 100))%" } ?? "Jev failed")
            }
            return .text(try await complete(model: route.model, prompt: route.prompt, input: input))

        case .branch(let question, let branches):
            let input = try text(of: payload)
            guard !branches.isEmpty else { throw PipelineError.noBranches }
            let t0 = Date()
            var chosen = 0
            var confidence: Double?
            do {
                let pick = try await JevClient.shared.choose(input: input, question: question, options: branches.map { ($0.name, $0.when) })
                chosen = pick.index
                confidence = pick.probability
            } catch {
                // Without Jev the first branch runs, so the track keeps working.
                NSLog("VoiceTools: Jev branching failed, taking the first branch: \(error)")
            }
            let jevMs = Int(Date().timeIntervalSince(t0) * 1000)
            let branch = branches[chosen]
            let pick = confidence.map { "Jev \(jevMs) ms → \(branch.name) \(Int($0 * 100))%" } ?? "Jev failed → \(branch.name)"
            let index = run?.currentStep ?? 0
            if !nested, run?.trackID == track.id, index < (run?.stepTitles.count ?? 0) {
                run?.stepTitles[index] = "Branch · \(pick)"
                run?.modelInfo = pick
                run?.branchDetail[index] = (jevMs, [])
            }
            if run?.trackID == track.id {
                run?.log.append(RunRecord.LogEntry(
                    title: "Branch · \(pick)", category: kind.category, depth: depth, ms: jevMs, input: Self.describe(payload),
                    decision: RunRecord.Decision(kind: "branch", question: question, chosen: branch.name, confidence: confidence, jevMs: jevMs,
                                                 others: branches.indices.filter { $0 != chosen }.map { branches[$0].name }),
                    status: .ok, message: branch.steps.isEmpty ? "no steps: the text passed through" : nil))
            }
            // The branch's steps, as a little track of their own (an LLM that fails can pass its input through).
            var current: Payload = .text(input)
            for step in branch.steps {
                let s0 = Date()
                current = try await runLogged(step, payload: current, track: track, depth: depth + 1, index: nil)
                if !nested, run?.trackID == track.id {
                    run?.branchDetail[index]?.steps.append(RunRecord.StepTiming(title: "\(branch.name) › \(step.kind.title)",
                                                                              ms: Int(Date().timeIntervalSince(s0) * 1000),
                                                                              category: step.kind.category))
                }
                if let text = current.text { run?.liveText = text }
            }
            return current

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
    case noBranches

    var errorDescription: String? {
        switch self {
        case .misplacedInput: "Microphone can only be the first step."
        case .noText: "No text found (nothing selected and clipboard empty)."
        case .expected(let kind): "This step expected \(kind.rawValue) input."
        case .noRoutes: "Route · Jev needs at least one route."
        case .noBranches: "Branch · Jev needs at least one branch."
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
