import AVFoundation
import NaturalLanguage
import Observation

/// Read-aloud playback with a macOS voice, an OpenRouter speech model, or an on-device model (Pocket TTS,
/// Supertonic-3). All can pause and resume where they left off and report progress for the UI.
@MainActor
@Observable
final class Speaker: NSObject {
    enum State { case idle, loading, speaking, paused }

    private(set) var state: State = .idle
    private(set) var sourceLabel = ""
    private(set) var voiceLabel = ""
    /// 0...1 through the whole text.
    private(set) var progress: Double = 0

    // macOS voices
    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var systemTextLength = 0

    // OpenRouter voices: the text is split into segments, each fetched while the previous one plays.
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var segments: [String] = []
    @ObservationIgnored private var segmentIndex = 0
    @ObservationIgnored private var fetches: [Int: Task<Data, Error>] = [:]
    @ObservationIgnored private var playbackRate: Float = 1
    @ObservationIgnored private var progressTimer: Timer?

    // On-device voices: generated audio is scheduled on a player node as it arrives.
    @ObservationIgnored private var audioEngine: AVAudioEngine?
    @ObservationIgnored private var playerNode: AVAudioPlayerNode?
    @ObservationIgnored private var pendingBuffers = 0
    @ObservationIgnored private var scheduledSamples: Int64 = 0
    @ObservationIgnored private var scheduledChars = 0
    @ObservationIgnored private var totalChars = 0
    @ObservationIgnored private var drained: CheckedContinuation<Void, Never>?

    @ObservationIgnored private var finished: CheckedContinuation<Void, Never>?
    @ObservationIgnored private var segmentDone: CheckedContinuation<Void, Never>?
    @ObservationIgnored private var generation = 0

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - macOS voice

    /// Speaks and returns when playback finishes or is cleared.
    func speakSystem(_ text: String, voiceID: String?, rate: Float, label: String) async {
        clear()
        sourceLabel = label
        let voice = voiceID.flatMap(AVSpeechSynthesisVoice.init(identifier:)) ?? Self.bestDefaultVoice
        voiceLabel = voice?.name ?? "System voice"
        systemTextLength = (text as NSString).length
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * rate)
        state = .speaking
        synthesizer.speak(utterance)
        await withCheckedContinuation { finished = $0 }
    }

    // MARK: - OpenRouter voice

    /// Fetches and plays speech segment by segment. Throws if the first segment can't be synthesized.
    func speakCloud(_ text: String, model: String, voice: String, rate: Float, label: String) async throws {
        clear()
        generation += 1
        let run = generation
        sourceLabel = label
        voiceLabel = OpenRouterCatalog.Model.voiceLabel(voice)
        segments = Self.segments(of: text)
        playbackRate = rate
        state = .loading

        let fetch: (Int) -> Task<Data, Error> = { index in
            let piece = self.segments[index]
            return Task { try await OpenRouterClient.shared.speech(model: model, voice: voice, text: piece) }
        }

        for index in segments.indices {
            guard generation == run else { return }
            segmentIndex = index
            let current = fetches[index] ?? fetch(index)
            fetches[index] = current
            // Keep the next segment downloading while this one plays.
            if index + 1 < segments.count, fetches[index + 1] == nil { fetches[index + 1] = fetch(index + 1) }

            let audio: Data
            do {
                audio = try await current.value
            } catch {
                guard generation == run else { return }
                clear()
                throw error
            }
            guard generation == run else { return }

            let player = try AVAudioPlayer(data: audio)
            player.delegate = self
            player.enableRate = true
            player.rate = playbackRate
            self.player = player
            if state != .paused { state = .speaking; player.play() }
            startProgressTimer()
            await withCheckedContinuation { segmentDone = $0 }
            fetches[index] = nil
        }
        if generation == run { finishPlayback() }
    }

    // MARK: - On-device voice

    /// Generates and plays speech on this Mac. Audio starts as soon as the first frames exist; later passages
    /// are generated while earlier ones play. Throws if the engine can't load or the first passage fails.
    func speakLocal(_ text: String, engine kind: LocalVoiceEngine, voice: String, rate: Float, label: String) async throws {
        clear()
        generation += 1
        let run = generation
        sourceLabel = label
        voiceLabel = "\(kind.voiceLabel(voice)) · \(kind.label)"
        state = .loading
        let passages = Self.segments(of: text)
        totalChars = passages.reduce(0) { $0 + $1.count }
        scheduledChars = 0
        scheduledSamples = 0
        pendingBuffers = 0

        let format = AVAudioFormat(standardFormatWithSampleRate: LocalVoices.sampleRate(kind), channels: 1)!
        let engine = AVAudioEngine()
        let node = AVAudioPlayerNode()
        let timePitch = AVAudioUnitTimePitch()
        timePitch.rate = rate
        engine.attach(node)
        engine.attach(timePitch)
        engine.connect(node, to: timePitch, format: format)
        engine.connect(timePitch, to: engine.mainMixerNode, format: format)
        try engine.start()
        audioEngine = engine
        playerNode = node
        startLocalProgressTimer()

        do {
            for passage in passages {
                for try await samples in try await LocalVoices.shared.stream(kind, text: passage, voice: voice) {
                    guard generation == run else { return }
                    schedule(samples, format: format, on: node, run: run)
                    if state == .loading {
                        state = .speaking
                        node.play()
                    }
                }
                guard generation == run else { return }
                scheduledChars += passage.count
            }
        } catch {
            guard generation == run else { return }
            clear()
            throw error
        }
        // Everything is generated; wait for the last buffer to finish playing.
        if pendingBuffers > 0 { await withCheckedContinuation { drained = $0 } }
        if generation == run {
            teardownLocal()
            finishPlayback()
        }
    }

    private func schedule(_ samples: [Float], format: AVAudioFormat, on node: AVAudioPlayerNode, run: Int) {
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        pendingBuffers += 1
        scheduledSamples += Int64(samples.count)
        node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == run else { return }
                self.pendingBuffers -= 1
                if self.pendingBuffers == 0 {
                    self.drained?.resume()
                    self.drained = nil
                }
            }
        }
    }

    private func startLocalProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            MainActor.assumeIsolated { self.updateLocalProgress() }
        }
    }

    private func updateLocalProgress() {
        guard let node = playerNode, let nodeTime = node.lastRenderTime,
              let playerTime = node.playerTime(forNodeTime: nodeTime), scheduledSamples > 0, totalChars > 0 else { return }
        // Estimate the whole text's length in samples from what's been generated so far.
        let charsSoFar = max(scheduledChars, 1)
        let estimatedTotal = Double(scheduledSamples) * Double(totalChars) / Double(charsSoFar)
        progress = min(1, Double(playerTime.sampleTime) / max(estimatedTotal, 1))
    }

    private func teardownLocal() {
        playerNode?.stop()
        audioEngine?.stop()
        playerNode = nil
        audioEngine = nil
        drained?.resume()
        drained = nil
        pendingBuffers = 0
    }

    func previewLocal(engine: LocalVoiceEngine, voice: String) async throws {
        let name = engine.voiceLabel(voice)
        try await speakLocal("Hi, I'm \(name). This is how I'll sound reading to you.", engine: engine, voice: voice,
                             rate: 1, label: "Voice preview")
    }

    /// Previews a voice with a short sentence, interrupting anything playing.
    func preview(model: String, voice: String) async throws {
        let name = OpenRouterCatalog.Model.voiceLabel(voice).components(separatedBy: " (").first ?? "this voice"
        try await speakCloud("Hi, I'm \(name). This is how I'll sound reading to you.", model: model, voice: voice,
                             rate: 1, label: "Voice preview")
    }

    // MARK: - Controls

    func togglePause() {
        switch state {
        case .speaking:
            if let playerNode { playerNode.pause() } else if let player { player.pause() } else { synthesizer.pauseSpeaking(at: .word) }
            state = .paused
        case .paused:
            if let playerNode { playerNode.play() } else if let player { player.play() } else { synthesizer.continueSpeaking() }
            state = .speaking
        case .idle, .loading:
            break
        }
    }

    /// Replays the current passage from its start (OpenRouter voices; macOS voices can't seek).
    func back() {
        player?.currentTime = 0
    }

    var canGoBack: Bool { player != nil }

    func clear() {
        generation += 1
        synthesizer.stopSpeaking(at: .immediate)
        player?.stop()
        player = nil
        teardownLocal()
        fetches.values.forEach { $0.cancel() }
        fetches.removeAll()
        segments = []
        progressTimer?.invalidate()
        progressTimer = nil
        segmentDone?.resume()
        segmentDone = nil
        finishPlayback()
        progress = 0
    }

    private func finishPlayback() {
        state = .idle
        progressTimer?.invalidate()
        progressTimer = nil
        finished?.resume()
        finished = nil
    }

    private func startProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            MainActor.assumeIsolated { self.updateCloudProgress() }
        }
    }

    private func updateCloudProgress() {
        guard !segments.isEmpty else { return }
        let total = segments.reduce(0) { $0 + $1.count }
        let done = segments.prefix(segmentIndex).reduce(0) { $0 + $1.count }
        let fraction = player.map { $0.duration > 0 ? $0.currentTime / $0.duration : 0 } ?? 0
        progress = (Double(done) + fraction * Double(segments[segmentIndex].count)) / Double(max(total, 1))
    }

    /// Splits text into sentence groups: a short first segment so audio starts quickly, longer ones after.
    static func segments(of text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var sentences: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let s = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { sentences.append(s) }
            return true
        }
        if sentences.isEmpty { sentences = [text] }

        var result: [String] = []
        var current = ""
        for sentence in sentences {
            let limit = result.isEmpty ? 240 : 1_200
            if !current.isEmpty, current.count + sentence.count + 1 > limit {
                result.append(current)
                current = ""
            }
            current += current.isEmpty ? sentence : " " + sentence
            // Split a single very long "sentence" (no punctuation) at word boundaries.
            while current.count > 2_000 {
                let cut = current.index(current.startIndex, offsetBy: 1_500)
                let space = current[..<cut].lastIndex(of: " ") ?? cut
                result.append(String(current[..<space]))
                current = String(current[space...]).trimmingCharacters(in: .whitespaces)
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    /// Highest-quality installed voice for the user's language.
    static var bestDefaultVoice: AVSpeechSynthesisVoice? {
        let language = AVSpeechSynthesisVoice.currentLanguageCode()
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == language }
            .max { $0.quality.rawValue < $1.quality.rawValue }
            ?? AVSpeechSynthesisVoice(language: language)
    }
}

extension Speaker: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString range: NSRange,
                                       utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.progress = Double(range.location + range.length) / Double(max(self.systemTextLength, 1))
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finishPlayback() }
    }
}

extension Speaker: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            guard player === self.player else { return }
            self.segmentDone?.resume()
            self.segmentDone = nil
        }
    }
}
