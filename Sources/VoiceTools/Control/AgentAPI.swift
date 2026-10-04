import AppKit
@preconcurrency import AVFoundation
import Foundation

/// What `vp` can ask the running app to do. Every command answers with one result or one error (see ControlServer);
/// long ones (run, say, listen, ask, transcribe, auth login) answer when they finish.
extension AppState {
    func handleControl(_ cmd: String, _ args: [String: Any], _ reply: ControlReply) {
        Task {
            do {
                try await dispatch(cmd, args, reply)
            } catch let error as AgentError {
                reply.error(error.code, error.message, hint: error.hint)
            } catch {
                reply.error("failed", error.localizedDescription)
            }
        }
    }

    private func dispatch(_ cmd: String, _ args: [String: Any], _ reply: ControlReply) async throws {
        switch cmd {
        case "ping":
            reply.result(["version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev",
                          "pid": Int(ProcessInfo.processInfo.processIdentifier)])
        case "status":
            reply.result(statusData())
        case "tracks":
            reply.result(["tracks": store.tracks.map(trackData)])
        case "tracks.enable":
            let index = try trackIndex(args)
            let on = args["enabled"] as? Bool ?? true
            store.tracks[index].enabled = on
            reply.result(["track": trackData(store.tracks[index])])
        case "run":
            reply.result(try await agentRun(args))
        case "say":
            reply.result(try await agentSay(args))
        case "stop":
            let was = speaker.state != .idle || capture != nil || agentRecording
            speaker.clear()
            cancelCapture()
            if agentRecording { agentCancelled = true }
            reply.result(["stopped": was])
        case "pause", "resume":
            let paused = speaker.state == .paused
            if speaker.state != .idle, (cmd == "pause") != paused { speaker.togglePause() }
            reply.result(["state": "\(speaker.state)"])
        case "listen":
            reply.result(try await agentListen(args))
        case "ask":
            // voice_model speaks the question; model (if any) transcribes the answer.
            var speech = args
            speech["text"] = args["question"] ?? ""
            speech["model"] = args["voice_model"]
            _ = try await agentSay(speech)
            reply.result(try await agentListen(args))
        case "transcribe":
            reply.result(try await agentTranscribe(args))
        case "watch":
            watchers.append(reply)
            reply.event(["event": "watch.started"])
        case "auth.status":
            reply.result(["providers": Providers.all.map { providerData($0) }])
        case "auth.set":
            let provider = try Providers.named(args["provider"] as? String)
            guard let key = (args["key"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
                throw AgentError("missing_key", "No key given.", hint: "echo \"$KEY\" | vp auth set \(provider.id)")
            }
            setKey(provider, key)
            reply.result(providerData(provider))
        case "auth.remove":
            let provider = try Providers.named(args["provider"] as? String)
            setKey(provider, "")
            reply.result(providerData(provider))
        case "auth.login":
            let provider = try Providers.named(args["provider"] as? String)
            guard provider.id == "openrouter" else {
                throw AgentError("no_login", "\(provider.name) has no browser login; set its key instead.",
                                 hint: "echo \"$KEY\" | vp auth set \(provider.id)")
            }
            let key = try await OpenRouterLogin.shared.run(headless: args["headless"] as? Bool ?? false, code: args["code"] as? String) { url in
                reply.event(["event": "auth.open", "url": url.absoluteString])
            }
            if let key {
                setKey(provider, key)
                reply.result(providerData(provider))
            } else {
                reply.result(["pending": true])
            }
        case "secret.list":
            reply.result(["secrets": Secrets.names()])
        case "secret.set":
            guard let name = args["name"] as? String, Secrets.isValidName(name) else {
                throw AgentError("bad_name", "Secret names use letters, digits, dashes and underscores.")
            }
            guard let value = args["value"] as? String, !value.isEmpty else { throw AgentError("missing_value", "No value given.") }
            Secrets.set(name, value)
            reply.result(["name": name, "set": true])
        case "secret.remove":
            guard let name = args["name"] as? String else { throw AgentError("bad_name", "Which secret?") }
            Secrets.set(name, nil)
            reply.result(["name": name, "set": false])
        case "open":
            try openWindow(args)
            // Answer with what's on screen once the windows have taken the request.
            try await Task.sleep(nanoseconds: 600_000_000)
            reply.result(uiState())
        case "close":
            try closeWindow(args["target"] as? String ?? "main")
            try await Task.sleep(nanoseconds: 400_000_000)
            reply.result(uiState())
        case "ui":
            reply.result(uiState())
        case "reading":
            guard let name = args["action"] as? String, let action = ReadingSettings.Action(rawValue: name) else {
                throw AgentError("bad_value", "Unknown reading action.", hint: "vp next | vp prev")
            }
            guard speaker.state != .idle else { throw AgentError("not_speaking", "Nothing is being read aloud.", hint: "vp say \"…\"") }
            readingAction(action)
            try await Task.sleep(nanoseconds: 150_000_000)
            reply.result(["sentence": speaker.currentSentence + 1, "of": speaker.sentences.count, "speed": Double(speaker.rate)])
        case "speed":
            guard let value = (args["speed"] as? Double) ?? (args["speed"] as? String).flatMap(Double.init), (0.6...2.0).contains(value) else {
                throw AgentError("bad_value", "Speed is 0.6 to 2.0.", hint: "vp speed 1.3")
            }
            guard speaker.state != .idle else { throw AgentError("not_speaking", "Nothing is being read aloud.", hint: "vp say \"…\" --speed \(value)") }
            speaker.setRate(Float(value))
            reply.result(["speed": Double(speaker.rate)])
        case "config.reload":
            store.reloadFromDisk()
            VocabularyStore.shared.reloadFromDisk()
            reply.result(["issues": (store.issues + VocabularyStore.shared.issues).map(\.description)])
        case "vocab.train":
            guard let word = (args["word"] as? String)?.trimmingCharacters(in: .whitespaces), !word.isEmpty else {
                throw AgentError("missing_word", "Which word?")
            }
            if !VocabularyStore.shared.entries.contains(where: { $0.write.lowercased() == word.lowercased() }) {
                VocabularyStore.shared.entries.append(VocabularyEntry(write: word, heardAs: []))
            }
            pendingTraining = word
            try openWindow(["target": "vocabulary"])
            reply.result(["word": word, "opened": "training"])
        case "models":
            let capability: OpenRouterCatalog.Capability = switch args["capability"] as? String {
            case "transcription": .transcription
            case "speech": .speech
            default: .text
            }
            let catalog = OpenRouterCatalog.shared
            catalog.refreshIfStale()
            reply.result(["models": catalog.models(for: capability).map { ["id": $0.id, "name": $0.shortName, "price": $0.shortPrice(for: capability) ?? ""] },
                          "updated": catalog.updated.map { ISO8601DateFormatter().string(from: $0) } ?? ""])
        case "voices":
            reply.result(["voices": voicesData(model: args["model"] as? String ?? "pocket")])
        case "update.check":
            NotificationCenter.default.post(name: .voicePipesCheckForUpdates, object: nil)
            reply.result(["checking": true])
        default:
            throw AgentError("unknown_command", "The app doesn't know '\(cmd)'.", hint: "Update Voice Pipes, or run `vp help`.")
        }
    }

    // MARK: Data

    func trackData(_ track: Track) -> [String: Any] {
        [
            "id": track.slug ?? ConfigFile.slug(track.name),
            "name": track.name,
            "enabled": track.enabled,
            "hotkeys": track.triggers.map { "\(KeyNames.format($0.combo)) \($0.mode == .hold ? "hold" : "toggle")" },
            "steps": track.steps.map(\.kind.chip),
            "takesText": track.steps.contains { $0.kind.input == .text },
        ]
    }

    private func statusData() -> [String: Any] {
        let parakeet: String = switch parakeetState {
        case .ready: "loaded"
        case .loading: ModelDownloads.shared.status[.parakeet].map { $0.preparing ? "preparing" : "downloading \(Int($0.fraction * 100))%" } ?? "loading"
        case .notLoaded: "not loaded"
        case .failed(let e): "failed: \(e)"
        }
        var models: [String: String] = ["parakeet": parakeet]
        for engine in LocalVoiceEngine.allCases {
            models[engine.rawValue] = switch localVoiceStates[engine] ?? .notLoaded {
            case .ready: "loaded"
            case .loading: "loading"
            case .notLoaded: "not loaded"
            case .failed(let e): "failed: \(e)"
            }
        }
        let running: [String: Any] = run.map { ["track": $0.trackName, "phase": "\($0.phase)"] } ?? [:]
        return [
            "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev",
            "microphone": AVCaptureDevice.authorizationStatus(for: .audio) == .authorized ? "allowed" : "not allowed",
            "accessibility": AXIsProcessTrusted() ? "allowed" : "not allowed",
            "models": models,
            "providers": Providers.all.map { providerData($0) },
            "checks": checks.map { ["level": SetupView.code($0.level), "title": $0.title, "detail": $0.detail] },
            "config": ["path": store.configURL.path, "issues": (store.issues + VocabularyStore.shared.issues).map(\.description)],
            "tracks": store.tracks.count,
            "running": running,
            "speaker": "\(speaker.state)",
        ]
    }

    private func providerData(_ provider: Providers.Provider) -> [String: Any] {
        let hint: String? = provider.id == "openrouter" ? openRouterKeyHint : jevKeyHint
        var data: [String: Any] = ["id": provider.id, "name": provider.name, "set": hint != nil, "used_for": provider.usedFor]
        if let hint { data["key"] = hint }
        if provider.id == "openrouter", let state = openRouterKeyState { data["state"] = "\(state)" }
        return data
    }

    private func setKey(_ provider: Providers.Provider, _ key: String) {
        if provider.id == "openrouter" { setOpenRouterKey(key) } else { setJevKey(key) }
    }

    private func voicesData(model: String) -> [[String: Any]] {
        switch model {
        case "pocket", "supertonic":
            let engine: LocalVoiceEngine = model == "pocket" ? .pocket : .supertonic
            return engine.voices.map { ["id": $0, "name": engine.voiceLabel($0), "default": $0 == engine.defaultVoice] }
        case "macos":
            return AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }
                .map { ["id": $0.identifier, "name": "\($0.name) (\($0.language))", "default": false] }
        default:
            return (OpenRouterCatalog.shared.model(model)?.voicesEnglishFirst ?? [])
                .map { ["id": $0, "name": OpenRouterCatalog.Model.voiceLabel($0), "default": false] }
        }
    }

    private func trackIndex(_ args: [String: Any]) throws -> Int {
        guard let id = args["track"] as? String else { throw AgentError("missing_track", "Which track?", hint: "vp tracks") }
        let key = id.lowercased()
        if let index = store.tracks.firstIndex(where: { $0.slug == key || $0.name.lowercased() == key }) { return index }
        throw AgentError("no_such_track", "No track '\(id)'.\(TableReader.suggestion(id, store.tracks.compactMap(\.slug)))", hint: "vp tracks")
    }

    // MARK: Running

    /// A run in progress (from a hotkey or another vp command) owns the HUD; wait or stop it.
    private func ensureIdle() throws {
        let active: Bool = switch run?.phase {
        case .recording, .processing, .speaking: true
        default: false
        }
        guard capture == nil, !agentRecording, !active else {
            throw AgentError("busy", "\(run?.trackName ?? "A track") is running.", hint: "vp stop   (or wait, then retry)")
        }
    }

    /// Runs a track. With text, it starts at the first block that takes text; a microphone track without text records
    /// until you stop talking. Answers with the final text.
    private func agentRun(_ args: [String: Any]) async throws -> [String: Any] {
        try ensureIdle()
        let track = store.tracks[try trackIndex(args)]
        if let error = track.validationError { throw AgentError("invalid_track", error, hint: "vp tracks show \(track.slug ?? "")") }
        let text = args["text"] as? String
        func begin() {
            run = ActiveRun(trackID: track.id, trackName: track.name, colorHex: track.colorHex,
                            stepTitles: track.steps.map(\.kind.title), phase: .processing, currentStep: 0,
                            stepMs: Array(repeating: nil, count: track.steps.count), heldBy: "vp")
        }
        let outcome: RunOutcome
        if let text {
            guard let start = track.steps.firstIndex(where: { $0.kind.input == .text }) else {
                throw AgentError("takes_no_text", "\(track.name) has no block that takes text.", hint: "Run it without --text, or add a text block.")
            }
            begin()
            outcome = await runSteps(track, from: start, payload: .text(text))
        } else if case .microphone = track.steps[0].kind {
            let samples = try await recordUntilSilence(label: track.name, track: track, args: args)
            begin()
            outcome = await runSteps(track, from: 1, payload: .audio(samples))
        } else {
            begin()
            outcome = await runSteps(track, from: 0, payload: .none)
        }
        if let failure = outcome.failure { throw AgentError("run_failed", failure, hint: "vp history --limit 1") }
        return ["track": track.slug ?? "", "text": outcome.text ?? "", "ms": outcome.totalMs]
    }

    /// Speaks text with a speech model (default: Pocket TTS on this Mac). Answers when it's finished.
    private func agentSay(_ args: [String: Any]) async throws -> [String: Any] {
        try ensureIdle()
        guard let text = (args["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            throw AgentError("missing_text", "Nothing to say.", hint: "vp say \"Build passed\"")
        }
        let model = args["model"] as? String ?? "pocket"
        let speed = Float(args["speed"] as? Double ?? 1.0)
        guard (0.6...2.0).contains(speed) else { throw AgentError("bad_speed", "Speed is 0.6–2.0.") }
        let voice = args["voice"] as? String
        let kind: StepKind
        switch model {
        case "pocket", "supertonic":
            let engine: LocalVoiceEngine = model == "pocket" ? .pocket : .supertonic
            let chosen = voice ?? engine.defaultVoice
            guard engine.voices.contains(chosen) else {
                throw AgentError("no_such_voice", "'\(chosen)' isn't a \(engine.label) voice.\(TableReader.suggestion(chosen, engine.voices))", hint: "vp voices --model \(model)")
            }
            kind = .localSpeech(engine: engine, voice: chosen, rate: speed)
        case "macos":
            kind = .speak(voiceID: voice, rate: speed)
        default:
            guard model.contains("/") else { throw AgentError("bad_model", "Use pocket, supertonic, macos or an OpenRouter speech model id.", hint: "vp models --capability speech") }
            kind = .openRouterSpeech(model: model, voice: voice ?? "", rate: speed)
        }
        let track = Track(slug: "vp-say", name: "vp say", colorHex: "#C3A3D4", triggers: [], steps: [Step(kind: kind)])
        run = ActiveRun(trackID: track.id, trackName: track.name, colorHex: track.colorHex, stepTitles: [kind.title],
                        phase: .processing, currentStep: 0, stepMs: [nil], heldBy: "vp")
        let outcome = await runSteps(track, from: 0, payload: .text(text))
        if let failure = outcome.failure { throw AgentError("speak_failed", failure) }
        return ["said": text, "model": model, "ms": outcome.totalMs]
    }

    /// Records until you stop talking (or `max` seconds), then transcribes.
    private func agentListen(_ args: [String: Any]) async throws -> [String: Any] {
        try ensureIdle()
        let samples = try await recordUntilSilence(label: "Listening (vp)", track: nil, args: args)
        let listening = run?.trackID
        // Whatever happens, the HUD doesn't stay on "processing".
        defer { if run?.trackID == listening { run = nil } }
        let model = args["model"] as? String ?? "parakeet"
        let t0 = Date()
        let text = model == "parakeet"
            ? try await parakeet.transcribe(samples)
            : try await OpenRouterClient.shared.transcribe(wav: WAV.encode(samples), model: model)
        return ["text": text, "seconds": Double(samples.count) / AudioRecorder.sampleRate, "ms": Int(Date().timeIntervalSince(t0) * 1000)]
    }

    private func agentTranscribe(_ args: [String: Any]) async throws -> [String: Any] {
        guard let path = args["path"] as? String else { throw AgentError("missing_file", "Which file?") }
        let samples = try AudioFileReader.samples(URL(fileURLWithPath: path))
        let model = args["model"] as? String ?? "parakeet"
        let t0 = Date()
        let text = model == "parakeet"
            ? try await parakeet.transcribe(samples)
            : try await OpenRouterClient.shared.transcribe(wav: WAV.encode(samples), model: model)
        return ["text": text, "seconds": Double(samples.count) / AudioRecorder.sampleRate, "ms": Int(Date().timeIntervalSince(t0) * 1000)]
    }

    /// The microphone until there's been speech and then `silence` seconds of quiet, or `max` seconds in all. The HUD
    /// shows REC meanwhile, like a hotkey recording.
    private func recordUntilSilence(label: String, track: Track?, args: [String: Any]) async throws -> [Float] {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw AgentError("no_microphone", "Voice Pipes isn't allowed to use the microphone.", hint: "vp open setup")
        }
        let maxSeconds = args["max"] as? Double ?? 30
        let silence = args["silence"] as? Double ?? 1.2
        run = ActiveRun(trackID: track?.id ?? UUID(), trackName: label, colorHex: track?.colorHex ?? "#E0694A",
                        stepTitles: track?.steps.map(\.kind.title) ?? ["Microphone"], phase: .recording, currentStep: 0,
                        stepMs: Array(repeating: nil, count: max(1, track?.steps.count ?? 1)), heldBy: "vp")
        run?.recordingStarted = Date()
        let meter = LevelGate(silence: silence)
        beginAgentRecording()
        defer { endAgentRecording() }
        let recorder = recorder(for: track.map(input(for:)) ?? store.input)
        recorder.onSamples = nil
        recorder.onLevel = { [weak self] level in
            meter.add(level)
            Task { @MainActor in self?.run?.level = level }
        }
        do { try recorder.start() } catch {
            run = nil
            throw AgentError("no_microphone", "Microphone unavailable: \(error.localizedDescription)")
        }
        let started = Date()
        while Date().timeIntervalSince(started) < maxSeconds, !meter.done, !agentCancelled {
            try? await Task.sleep(for: .milliseconds(100))
        }
        let samples = recorder.stop()
        guard !agentCancelled else {
            run = nil
            throw AgentError("cancelled", "Stopped (vp stop or Esc).")
        }
        run?.phase = .processing
        run?.processingStarted = Date()
        guard samples.count > Int(AudioRecorder.sampleRate * 0.3), meter.heardSpeech else {
            run = nil
            throw AgentError("no_speech", "Didn't hear anything.", hint: "Check the input device, or raise --max.")
        }
        return samples
    }

    // MARK: Windows and what they show

    private func openWindow(_ args: [String: Any]) throws {
        let nav = UINav.shared
        let target = args["target"] as? String ?? "main"
        nav.quietOpen = args["background"] as? Bool ?? false
        func int(_ name: String) throws -> Int? {
            guard let raw = args[name] else { return nil }
            guard let value = (raw as? Int) ?? (raw as? String).flatMap(Int.init), value >= 1 else {
                throw AgentError("bad_value", "--\(name) is a number from 1.")
            }
            return value
        }
        switch target {
        case "main":
            break
        case "menu":
            MenuBarPanel.open()
            return
        case "reading":
            readAlong = true  // shows with the next (or current) read-aloud
            return
        case "setup":
            mainSection = .setup
            if let section = args["section"] as? String {
                guard SetupView.sections.contains(section) else {
                    throw AgentError("no_such_section", "Setup has no section '\(section)'.\(TableReader.suggestion(section, SetupView.sections))",
                                     hint: "sections: " + SetupView.sections.joined(separator: ", "))
                }
                nav.setupSection = section
            }
            if let field = args["field"] as? String {
                let fields = ["openrouter-key", "typesafe-key"]
                guard fields.contains(field) else {
                    throw AgentError("no_such_field", "Setup has no field '\(field)'.\(TableReader.suggestion(field, fields))", hint: "fields: " + fields.joined(separator: ", "))
                }
                nav.setupSection = "connections"
                nav.focusField(field)
            }
        case "history":
            mainSection = .activity
            var request = UINav.HistoryRequest()
            if args["track"] != nil { request.track = store.tracks[try trackIndex(args)].name }
            request.search = args["search"] as? String
            if let n = try int("run") {
                guard let run = historyStore.database?.run(number: n) else {
                    throw AgentError("no_such_run", "History has \(historyStore.count) runs.", hint: "vp history")
                }
                request.run = run.id
            }
            nav.history = request
            if args["field"] as? String == "search" { nav.focusField("search") }
        case "vocabulary":
            mainSection = .vocabulary
            let word = args["word"] as? String
            if let word, !VocabularyStore.shared.entries.contains(where: { $0.write.lowercased() == word.lowercased() }) {
                throw AgentError("no_such_word", "'\(word)' isn't in Vocabulary.\(TableReader.suggestion(word, VocabularyStore.shared.entries.map(\.write)))",
                                 hint: "vp vocab add \"\(word)\"")
            }
            nav.vocabulary = .init(word: word, add: args["add"] as? Bool ?? false)
            if args["field"] as? String == "try" { nav.focusField("try") }
        case "track":
            let track = store.tracks[try trackIndex(args)]
            let id = track.slug ?? track.name
            mainSection = .track(track.id)
            var request = UINav.EditorRequest(track: track.id)
            if let n = try int("step") {
                guard track.steps.indices.contains(n - 1) else {
                    throw AgentError("no_such_step", "\(id) has \(track.steps.count) step\(track.steps.count == 1 ? "" : "s").", hint: "vp tracks show \(id)")
                }
                request.step = n
            }
            if let r = try int("route") {
                guard let n = request.step, let routes = track.steps[n - 1].kind.routes else {
                    throw AgentError("not_a_route", "--route needs --step pointing at a route step.", hint: "vp tracks show \(id)")
                }
                guard routes.indices.contains(r - 1) else { throw AgentError("no_such_route", "That step has \(routes.count) routes.", hint: "vp tracks show \(id)") }
                request.route = r
            }
            if let section = args["section"] as? String {
                let sections = ["title", "triggers", "pipeline"]
                guard sections.contains(section) else {
                    throw AgentError("no_such_section", "The editor has no section '\(section)'.", hint: "sections: " + sections.joined(separator: ", "))
                }
                request.section = section
            }
            if let field = args["field"] as? String {
                let fields = Self.editorFields(track, step: request.step, route: request.route)
                guard fields.contains(field) else {
                    throw AgentError("no_such_field", "No field '\(field)' there.\(TableReader.suggestion(field, fields))",
                                     hint: fields.isEmpty ? "this block has no text fields"
                                         : "fields: " + fields.joined(separator: ", ") + (request.step == nil ? " (a block's fields need --step <n>)" : ""))
                }
                nav.focusField(request.route.map { "route\($0).\(field)" } ?? field)
            }
            nav.editor = request
        case "about":
            NotificationCenter.default.post(name: .voicePipesOpenWindow, object: "about")
            return
        case "onboarding":
            if let name = args["step"] as? String {
                guard let index = OnboardingView.stepNames.firstIndex(of: name) else {
                    throw AgentError("no_such_step", "Setup has no step '\(name)'.", hint: "steps: " + OnboardingView.stepNames.joined(separator: ", "))
                }
                nav.onboardingStep = index
            }
            OnboardingController.shared.show(self)
            return
        case "config":
            NSWorkspace.shared.open(store.configURL)
            return
        default:
            throw AgentError("no_such_target", "Can't open '\(target)'.\(TableReader.suggestion(target, Self.openTargets))",
                             hint: "vp open " + Self.openTargets.joined(separator: "|"))
        }
        NotificationCenter.default.post(name: .voicePipesOpenWindow, object: "main")
    }

    static let openTargets = ["main", "menu", "reading", "track", "history", "vocabulary", "setup", "onboarding", "about", "config"]

    /// The text fields `--field` can focus: the track's name, or the chosen block's (config file names).
    static func editorFields(_ track: Track, step: Int?, route: Int?) -> [String] {
        guard let step else { return ["name"] }
        if route != nil { return ["name", "when", "prompt"] }
        return switch track.steps[step - 1].kind {
        case .llm: ["prompt"]
        case .http: ["url", "headers", "body", "response_field"]
        case .template: ["template"]
        default: []
        }
    }

    private func closeWindow(_ target: String) throws {
        let targets = ["main", "menu", "reading", "about", "onboarding", "sheet", "all"]
        guard targets.contains(target) else {
            throw AgentError("no_such_target", "Can't close '\(target)'.\(TableReader.suggestion(target, targets))", hint: "vp close " + targets.joined(separator: "|"))
        }
        if target == "sheet" || target == "all" { UINav.shared.dismissSheets += 1 }
        if target == "menu" || target == "all" { MenuBarPanel.close() }
        if target == "reading" { readAlong = false }
        if target == "onboarding" || target == "all" { OnboardingController.shared.close() }
        for name in ["main", "about"] where target == name || target == "all" {
            for window in NSApp.windows where window.identifier?.rawValue.hasPrefix(name) == true { window.close() }
        }
    }

    /// What's on screen, for `vp ui` (and the answer to open/close).
    func uiState() -> [String: Any] {
        let nav = UINav.shared
        func named(_ window: NSWindow) -> String? {
            if let id = window.identifier?.rawValue, let name = ["main", "about"].first(where: { id.hasPrefix($0) }) { return name }
            if window.title == OnboardingController.title { return "onboarding" }
            return nil
        }
        var windows = NSApp.windows.filter(\.isVisible).compactMap(named)
        if MenuBarPanel.isOpen { windows.append("menu") }
        var state: [String: Any] = [
            "windows": Array(Set(windows)).sorted(),
            "front": NSApp.isActive ? (NSApp.keyWindow.flatMap(named) ?? (MenuBarPanel.isOpen ? "menu" : "other")) : "another app",
        ]
        if windows.contains("main") {
            switch mainSection {
            case .track(let id):
                let track = store.tracks.first { $0.id == id }
                state["page"] = "track"
                state["track"] = track.map { $0.slug ?? $0.name } ?? NSNull()
                state["step"] = nav.expandedStep ?? NSNull()
                if !nav.editingRoutes.isEmpty { state["routes_open"] = nav.editingRoutes }
            case .activity:
                state["page"] = "history"
                state["filter"] = nav.historyTrack ?? "all"
                if !nav.historySearch.isEmpty { state["search"] = nav.historySearch }
            case .vocabulary: state["page"] = "vocabulary"
            case .setup, nil: state["page"] = "setup"
            }
        }
        if let field = nav.focusedField { state["field"] = field }
        state["reading"] = readAlong ? (speaker.state == .idle ? "open (shows when reading aloud)" : "open") : "closed"
        if speaker.state != .idle { state["speed"] = Double(speaker.rate) }
        if let sheet = nav.sheet { state["sheet"] = sheet }
        if windows.contains("onboarding"), let step = nav.currentOnboardingStep { state["onboarding_step"] = OnboardingView.stepNames[step] }
        return state
    }

    /// An outside edit to config.toml: flash what changed, and in the open editor scroll to it (opening a single
    /// new or changed block), so you can watch an agent build a track.
    func showExternalChanges(_ changes: [Track.ID: Track.Changes]) {
        var keys = Set<String>()
        for (id, change) in changes {
            keys.formUnion(change.steps.map { "step-\($0)" })
            if change.title { keys.insert("title-\(id)") }
            if change.triggers { keys.insert("triggers-\(id)") }
        }
        if case .track(let open) = mainSection, let change = changes[open], let track = store.tracks.first(where: { $0.id == open }),
           let first = change.steps.first, let index = track.steps.firstIndex(where: { $0.id == first }) {
            UINav.shared.editor = .init(track: open, step: index + 1, expand: change.steps.count == 1)
        }
        UINav.shared.highlight(keys)
    }
}

extension Notification.Name {
    static let voicePipesOpenWindow = Notification.Name("VoicePipes.openWindow")
    static let voicePipesCheckForUpdates = Notification.Name("VoicePipes.checkForUpdates")
}

/// Decides when someone has finished speaking: speech (level above `speech`), then `silence` seconds below `quiet`.
final class LevelGate: @unchecked Sendable {
    private let lock = NSLock()
    private let silence: TimeInterval
    private var lastLoud: Date?
    private(set) var heardSpeech = false

    init(silence: TimeInterval) { self.silence = silence }

    func add(_ level: Float) {
        lock.lock(); defer { lock.unlock() }
        if level > 0.08 { heardSpeech = true; lastLoud = Date() }
    }

    var done: Bool {
        lock.lock(); defer { lock.unlock() }
        guard heardSpeech, let lastLoud else { return false }
        return Date().timeIntervalSince(lastLoud) > silence
    }
}

struct AgentError: Error {
    let code: String
    let message: String
    let hint: String?
    init(_ code: String, _ message: String, hint: String? = nil) {
        self.code = code
        self.message = message
        self.hint = hint
    }
}

/// The providers whose keys `vp auth` manages.
enum Providers {
    struct Provider {
        let id: String
        let name: String
        let usedFor: String
    }

    static let all = [
        Provider(id: "openrouter", name: "OpenRouter", usedFor: "cloud transcription, LLM and route models, cloud voices"),
        Provider(id: "typesafe", name: "TypeSafe · Jev", usedFor: "Route steps (Jev picks the model) and word training"),
    ]

    static func named(_ name: String?) throws -> Provider {
        let key = (name ?? "").lowercased()
        let aliases = ["jev": "typesafe", "or": "openrouter", "open-router": "openrouter"]
        if let provider = all.first(where: { $0.id == (aliases[key] ?? key) }) { return provider }
        throw AgentError("no_such_provider", "No provider '\(name ?? "")'. Providers: \(all.map(\.id).joined(separator: ", ")).",
                         hint: "vp auth")
    }
}

/// Your own secrets for http blocks (`${secret:name}`), in the Keychain beside the provider keys.
enum Secrets {
    private static let prefix = "secret."
    private static let indexKey = "secrets.names"

    static func isValidName(_ name: String) -> Bool {
        !name.isEmpty && name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }

    static func names() -> [String] { (UserDefaults.standard.stringArray(forKey: indexKey) ?? []).sorted() }

    static func get(_ name: String) -> String? { Keychain.get(prefix + name) }

    static func set(_ name: String, _ value: String?) {
        Keychain.set(value, for: prefix + name)
        var all = Set(names())
        if value == nil { all.remove(name) } else { all.insert(name) }
        UserDefaults.standard.set(Array(all).sorted(), forKey: indexKey)
    }

    /// `${secret:name}` and `${env:NAME}` in a string. Unknown names become empty.
    static func interpolate(_ text: String) -> String {
        guard text.contains("${") else { return text }
        var out = text
        let pattern = try! NSRegularExpression(pattern: #"\$\{(secret|env):([A-Za-z0-9_\-]+)\}"#)
        for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let whole = Range(match.range, in: out), let kind = Range(match.range(at: 1), in: text),
                  let name = Range(match.range(at: 2), in: text) else { continue }
            let value = text[kind] == "secret" ? get(String(text[name])) : ProcessInfo.processInfo.environment[String(text[name])]
            out.replaceSubrange(whole, with: value ?? "")
        }
        return out
    }
}

/// Decodes any audio file AVFoundation reads into 16 kHz mono samples.
enum AudioFileReader {
    static func samples(_ url: URL) throws -> [Float] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AgentError("no_such_file", "No file at \(url.path).")
        }
        let file = try AVAudioFile(forReading: url)
        let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: AudioRecorder.sampleRate, channels: 1, interleaved: false)!
        guard let converter = AVAudioConverter(from: file.processingFormat, to: target) else {
            throw AgentError("bad_audio", "Can't convert \(url.lastPathComponent) to 16 kHz mono.")
        }
        let inputBuffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: inputBuffer)
        let ratio = target.sampleRate / file.processingFormat.sampleRate
        let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: AVAudioFrameCount(Double(file.length) * ratio) + 1024)!
        var fed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if fed { status.pointee = .endOfStream; return nil }
            fed = true
            status.pointee = .haveData
            return inputBuffer
        }
        if let error { throw error }
        return Array(UnsafeBufferPointer(start: output.floatChannelData![0], count: Int(output.frameLength)))
    }
}
