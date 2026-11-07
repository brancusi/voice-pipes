import AppKit
import Carbon.HIToolbox
import FluidAudio
import Observation

/// A voiceover take (`vp record-vo`): the script on the HUD's card, a countdown, then the microphone while the card
/// follows the reader; afterwards retake (all of it, or from a sentence), play back, keep or cancel.
@MainActor
@Observable
final class VoiceoverSession {
    enum Phase: Equatable { case countdown(Int), recording, aligning, review, playing }

    let script: VoiceoverScript
    let title: String
    let out: URL
    let countdown: Int
    let input: String
    var phase: Phase = .countdown(3)
    /// The card's cursor while recording (UTF-16 offset in the script).
    var position = 0
    var level: Float = 0
    var recordingStarted = Date()
    /// The take as aligned after it stopped.
    var alignment: VoiceoverScript.Alignment?
    var duration: Double = 0
    var problem: String?

    @ObservationIgnored let recorder = VoiceoverRecorder()
    @ObservationIgnored var follower: VoiceoverScript.Follower
    @ObservationIgnored var transcriber: StreamingTranscriber?
    @ObservationIgnored var take = 0
    @ObservationIgnored var lastVoice = Date()
    @ObservationIgnored var heard: [VoiceoverScript.HeardWord] = []
    @ObservationIgnored var done: CheckedContinuation<Bool, Never>?
    @ObservationIgnored var keys: [UInt32] = []

    init(script: VoiceoverScript, title: String, out: URL, countdown: Int, input: String) {
        self.script = script
        self.title = title
        self.out = out
        self.countdown = countdown
        self.input = input
        follower = VoiceoverScript.Follower(script: script)
    }

    var sentenceCount: Int { script.sentences.count }
    var matchedSentences: Int { alignment?.sentences.filter { $0.start != nil }.count ?? 0 }
}

extension AppState {
    struct VoiceoverResult {
        let accepted: Bool
        let audio: URL
        let timings: URL?
        let duration: Double
        let alignment: VoiceoverScript.Alignment?
        let sampleRate: Double
    }

    /// Runs a voiceover session until the take is kept or the session cancelled.
    func recordVoiceover(script: VoiceoverScript, title: String, out: URL, countdown: Int, input: String?) async throws -> VoiceoverResult {
        let session = VoiceoverSession(script: script, title: title, out: out, countdown: countdown, input: input ?? store.input)
        try session.recorder.open(input: session.input)
        session.recorder.onLevel = { [weak session] level in
            Task { @MainActor in
                guard let session else { return }
                session.level = level
                if level > 0.06 { session.lastVoice = Date() }
            }
        }
        voiceover = session
        run = ActiveRun(trackID: UUID(), trackName: title, colorHex: "#E0694A", stepTitles: ["Voiceover"], phase: .recording,
                        currentStep: 0, stepMs: [nil], heldBy: "vp")
        run?.microphone = session.recorder.deviceName
        bindVoiceoverKeys(session)
        startTake(session, from: nil)
        let accepted = await withCheckedContinuation { session.done = $0 }

        session.keys.forEach { hotkeys.remove($0) }
        session.transcriber?.cancel()
        session.recorder.close()
        if voiceover === session { voiceover = nil }
        run = nil

        guard accepted else {
            try? FileManager.default.removeItem(at: out)
            return VoiceoverResult(accepted: false, audio: out, timings: nil, duration: session.duration, alignment: nil,
                                   sampleRate: session.recorder.sampleRate)
        }
        let timings = out.deletingPathExtension().appendingPathExtension("timings.json")
        try writeTimings(session, to: timings)
        return VoiceoverResult(accepted: true, audio: out, timings: timings, duration: session.duration, alignment: session.alignment,
                               sampleRate: session.recorder.sampleRate)
    }

    // MARK: Keys

    /// While the session runs: Return stops a take, then keeps it; Esc stops, then cancels; R retakes; Space plays.
    private func bindVoiceoverKeys(_ session: VoiceoverSession) {
        let bindings: [(Int, () -> Void)] = [
            (kVK_Return, { [weak self] in self?.voiceoverReturn(session) }),
            (kVK_ANSI_KeypadEnter, { [weak self] in self?.voiceoverReturn(session) }),
            (kVK_Escape, { [weak self] in self?.voiceoverEscape(session) }),
            (kVK_ANSI_R, { [weak self] in self?.voiceoverRetake(session, from: nil) }),
            (kVK_Space, { [weak self] in self?.voiceoverPlay(session) }),
        ]
        session.keys = bindings.compactMap { code, action in
            hotkeys.add(KeyCombo(key: .init(code: UInt32(code)), modifiers: [])) { pressed in if pressed { action() } }
        }
    }

    func voiceoverReturn(_ session: VoiceoverSession) {
        switch session.phase {
        case .recording: stopTake(session)
        case .review, .playing: finishVoiceover(session, accepted: true)
        case .countdown, .aligning: break
        }
    }

    func voiceoverEscape(_ session: VoiceoverSession) {
        switch session.phase {
        case .recording: stopTake(session)
        case .playing: speaker.clear()
        case .countdown:
            // Back to the take there was, or out.
            session.take += 1
            if session.alignment != nil { session.phase = .review } else { finishVoiceover(session, accepted: false) }
        case .review: finishVoiceover(session, accepted: false)
        case .aligning: break
        }
    }

    func voiceoverRetake(_ session: VoiceoverSession, from sentence: Int?) {
        switch session.phase {
        case .playing:
            speaker.clear()
            startTake(session, from: sentence)
        case .recording:
            guard sentence == nil else { return }
            session.transcriber?.cancel()
            startTake(session, from: nil)
        case .review:
            startTake(session, from: sentence)
        case .countdown, .aligning:
            break
        }
    }

    func voiceoverPlay(_ session: VoiceoverSession) {
        switch session.phase {
        case .review:
            guard let alignment = session.alignment else { return }
            session.phase = .playing
            let marks = zip(session.script.words, alignment.words).map { PlaybackTranscript.Mark(offset: $0.range.location, time: $1.start) }
                .sorted { ($0.time, $0.offset) < ($1.time, $1.offset) }
            Task {
                try? await speaker.playFile(session.out, transcript: PlaybackTranscript(text: session.script.text, marks: marks),
                                            rate: 1, label: session.title)
                if session.phase == .playing { session.phase = .review }
            }
        case .playing:
            speaker.clear()
        default:
            break
        }
    }

    func finishVoiceover(_ session: VoiceoverSession, accepted: Bool) {
        session.take += 1
        if session.phase == .playing { speaker.clear() }
        session.done?.resume(returning: accepted)
        session.done = nil
    }

    // MARK: Takes

    /// A countdown, then recording: from the start, or from a sentence (the take up to it is kept).
    private func startTake(_ session: VoiceoverSession, from sentence: Int?) {
        session.take += 1
        let take = session.take
        session.recorder.pause()
        session.transcriber?.cancel()
        session.transcriber = nil
        // Where the take carries on: from the start, or in the pause before the sentence (just after the word before it).
        var cut = 0.0
        var firstToken = -1
        if let sentence, let times = session.alignment?.sentences[safe: sentence], let start = times.start {
            let before = session.alignment?.sentences[..<sentence].last { $0.end != nil }?.end ?? 0
            cut = max(before + 0.05, min(start - 0.1, (before + start) / 2))
            firstToken = session.script.sentenceTokens[sentence].lowerBound - 1
        }
        let follower = VoiceoverScript.Follower(script: session.script, from: firstToken)
        session.position = follower.position
        session.problem = nil

        Task {
            for n in stride(from: session.countdown, through: 1, by: -1) {
                guard session.take == take else { return }
                session.phase = .countdown(n)
                try? await Task.sleep(for: .seconds(1))
            }
            guard session.take == take else { return }
            // Only now, so Esc during the countdown leaves the last take as it was.
            session.recorder.truncate(to: cut)
            session.follower = follower
            let transcriber = StreamingTranscriber(parakeet: parakeet) { text in
                Task { @MainActor in
                    guard session.take == take, session.phase == .recording else { return }
                    session.follower.update(text)
                    session.position = session.follower.position
                }
            }
            session.transcriber = transcriber
            session.recorder.onSamples = { transcriber.feed($0) }
            session.recordingStarted = Date()
            session.lastVoice = Date()
            session.recorder.record()
            session.phase = .recording
            // Stops by itself a moment after the last line.
            while session.take == take, session.phase == .recording {
                try? await Task.sleep(for: .milliseconds(150))
                if session.follower.finished, Date().timeIntervalSince(session.lastVoice) > 1.6 { stopTake(session) }
            }
        }
    }

    /// Ends the take: writes the file, transcribes it whole and aligns the script.
    private func stopTake(_ session: VoiceoverSession) {
        guard session.phase == .recording else { return }
        session.take += 1
        let take = session.take
        session.recorder.pause()
        session.transcriber?.cancel()
        session.transcriber = nil
        session.phase = .aligning
        let audio = session.recorder.take
        session.duration = Double(audio.native.count) / session.recorder.sampleRate
        Task {
            do {
                try VoiceoverRecorder.write(audio.native, sampleRate: session.recorder.sampleRate, to: session.out)
                let words = try await parakeet.transcribeWords(audio.speech)
                session.heard = words.map { VoiceoverScript.HeardWord(word: $0.word, start: $0.startTime, end: $0.endTime) }
                session.alignment = session.script.align(session.heard)
            } catch {
                session.problem = error.localizedDescription
            }
            guard session.take == take else { return }
            session.position = (session.script.text as NSString).length
            session.phase = .review
        }
    }

    // MARK: The timings file

    private func writeTimings(_ session: VoiceoverSession, to url: URL) throws {
        func t(_ x: Double?) -> Any { x.map { ($0 * 1000).rounded() / 1000 } ?? NSNull() }
        let a = session.alignment
        let json: [String: Any] = [
            "text": session.script.text,
            "audio": session.out.path,
            "duration": t(session.duration),
            "sample_rate": Int(session.recorder.sampleRate),
            "words": (a?.words ?? []).map { ["word": $0.word, "start": t($0.start), "end": t($0.end), "matched": $0.matched] },
            "script": (a?.sentences ?? []).map { ["index": $0.index, "text": $0.text, "start": t($0.start), "end": t($0.end), "matched": $0.matched] },
            "markers": (a?.markers ?? []).map { ["id": $0.id, "time": t($0.time), "word": $0.word.map { $0 as Any } ?? NSNull()] },
            "heard": session.heard.map { ["word": $0.word, "start": t($0.start), "end": t($0.end)] },
        ]
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url)
    }
}
