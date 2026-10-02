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

    // Read-along (the HUD's expanded card): what's being read, by sentence, and where the voice is.
    struct Sentence: Identifiable, Equatable {
        let id: Int
        /// UTF-16 offset into `text`.
        let start: Int
        let text: String
        /// Starts a new paragraph (a line break before it).
        let opensParagraph: Bool
    }

    private(set) var text = ""
    private(set) var sentences: [Sentence] = []
    /// UTF-16 offset of the voice in `text`: exact for macOS voices (word by word), estimated from progress for
    /// the others.
    private(set) var position = 0
    /// Playback speed, changeable while reading (`setRate`).
    private(set) var rate: Float = 1

    var currentSentence: Int { sentences.lastIndex { $0.start <= position } ?? 0 }

    private enum Engine { case none, system, cloud, local }
    @ObservationIgnored private var engine: Engine = .none
    @ObservationIgnored private var textLength = 0

    // macOS voices
    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var systemVoice: AVSpeechSynthesisVoice?
    @ObservationIgnored private var currentUtterance: AVSpeechUtterance?
    /// Where the current utterance starts in `text` (a speed change restarts the rest of the text from the word
    /// being spoken: AVSpeechSynthesizer can't change rate mid-utterance).
    @ObservationIgnored private var systemBase = 0
    @ObservationIgnored private var systemRestartPending = false

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
    @ObservationIgnored private var timePitch: AVAudioUnitTimePitch?
    @ObservationIgnored private var pendingBuffers = 0
    @ObservationIgnored private var scheduledSamples: Int64 = 0
    @ObservationIgnored private var scheduledChars = 0
    @ObservationIgnored private var totalChars = 0
    @ObservationIgnored private var drained: CheckedContinuation<Void, Never>?

    @ObservationIgnored private var finished: CheckedContinuation<Void, Never>?
    @ObservationIgnored private var segmentDone: CheckedContinuation<Void, Never>?
    @ObservationIgnored private var generation = 0
    /// Cloud and on-device voices read in passes: the whole text, or from a sentence the user jumped to.
    @ObservationIgnored private var pass = 0
    @ObservationIgnored private var base = 0
    @ObservationIgnored private var seekTarget: Int?
    @ObservationIgnored private var sampleRate: Double = 24_000
    @ObservationIgnored private var completedSamples: Int64 = 0

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - macOS voice

    /// Speaks and returns when playback finishes or is cleared.
    func speakSystem(_ text: String, voiceID: String?, rate: Float, label: String) async {
        clear()
        begin(text, rate: rate, engine: .system)
        sourceLabel = label
        let voice = voiceID.flatMap(AVSpeechSynthesisVoice.init(identifier:)) ?? Self.bestDefaultVoice
        voiceLabel = voice?.name ?? "System voice"
        systemVoice = voice
        state = .speaking
        speakSystem(from: 0)
        await withCheckedContinuation { finished = $0 }
    }

    // MARK: - OpenRouter voice

    /// Fetches and plays speech segment by segment. Throws if the first segment can't be synthesized. Returns when
    /// the text is finished or cleared; a jump (`seek`) carries on from that sentence within the same call.
    func speakCloud(_ text: String, model: String, voice: String, rate: Float, label: String) async throws {
        clear()
        begin(text, rate: rate, engine: .cloud)
        generation += 1
        let run = generation
        sourceLabel = label
        voiceLabel = OpenRouterCatalog.Model.voiceLabel(voice)
        playbackRate = rate
        startProgressTimer()
        var from = 0
        while true {
            try await playCloud(from: from, model: model, voice: voice, run: run, pass: pass)
            guard generation == run else { return }
            guard let target = seekTarget else { break }
            seekTarget = nil
            from = target
        }
        finishPlayback()
    }

    /// One pass, from a UTF-16 offset to the end (or until a jump starts another).
    private func playCloud(from offset: Int, model: String, voice: String, run: Int, pass: Int) async throws {
        base = offset
        segments = Self.segments(of: suffix(from: offset))
        segmentIndex = 0
        state = .loading
        let fetch: (Int) -> Task<Data, Error> = { index in
            let piece = self.segments[index]
            return Task { try await OpenRouterClient.shared.speech(model: model, voice: voice, text: piece) }
        }
        for index in segments.indices {
            guard isCurrent(run, pass) else { return }
            segmentIndex = index
            let current = fetches[index] ?? fetch(index)
            fetches[index] = current
            // Keep the next segment downloading while this one plays.
            if index + 1 < segments.count, fetches[index + 1] == nil { fetches[index + 1] = fetch(index + 1) }

            let audio: Data
            do {
                audio = try await current.value
            } catch {
                guard isCurrent(run, pass) else { return }  // cancelled by a jump
                clear()
                throw error
            }
            guard isCurrent(run, pass) else { return }

            let player = try AVAudioPlayer(data: audio)
            player.delegate = self
            player.enableRate = true
            player.rate = playbackRate
            self.player = player
            if state != .paused { state = .speaking; player.play() }
            await withCheckedContinuation { segmentDone = $0 }
            fetches[index] = nil
        }
    }

    private func isCurrent(_ run: Int, _ pass: Int) -> Bool { generation == run && self.pass == pass }

    private func suffix(from offset: Int) -> String {
        let all = text as NSString
        return all.substring(from: min(max(0, offset), all.length))
    }

    // MARK: - On-device voice

    /// Generates and plays speech on this Mac. Audio starts as soon as the first frames exist; later passages
    /// are generated while earlier ones play. Throws if the engine can't load or the first passage fails.
    func speakLocal(_ text: String, engine kind: LocalVoiceEngine, voice: String, rate: Float, label: String) async throws {
        clear()
        begin(text, rate: rate, engine: .local)
        generation += 1
        let run = generation
        sourceLabel = label
        voiceLabel = "\(kind.voiceLabel(voice)) · \(kind.label)"
        state = .loading

        sampleRate = LocalVoices.sampleRate(kind)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
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
        self.timePitch = timePitch
        startLocalProgressTimer()

        var from = 0
        while true {
            do {
                try await playLocal(from: from, kind: kind, voice: voice, format: format, node: node, run: run, pass: pass)
            } catch {
                guard isCurrent(run, pass) else { return }
                clear()
                throw error
            }
            guard generation == run else { return }
            guard let target = seekTarget else { break }
            seekTarget = nil
            from = target
        }
        teardownLocal()
        finishPlayback()
    }

    /// One pass, from a UTF-16 offset to the end (or until a jump starts another). Returns once it has played out.
    private func playLocal(from offset: Int, kind: LocalVoiceEngine, voice: String, format: AVAudioFormat,
                           node: AVAudioPlayerNode, run: Int, pass: Int) async throws {
        base = offset
        let passages = Self.segments(of: suffix(from: offset))
        totalChars = passages.reduce(0) { $0 + $1.count }
        scheduledChars = 0
        scheduledSamples = 0
        completedSamples = 0
        pendingBuffers = 0
        state = .loading
        for passage in passages {
            for try await samples in try await LocalVoices.shared.stream(kind, text: passage, voice: voice) {
                guard isCurrent(run, pass) else { return }
                schedule(samples, format: format, on: node, run: run, pass: pass)
                if state == .loading {
                    state = .speaking
                    node.play()
                }
            }
            guard isCurrent(run, pass) else { return }
            scheduledChars += passage.count
            completedSamples = scheduledSamples
        }
        // Everything is generated; wait for the last buffer to finish playing (a jump ends the wait).
        if pendingBuffers > 0 { await withCheckedContinuation { drained = $0 } }
    }

    private func schedule(_ samples: [Float], format: AVAudioFormat, on node: AVAudioPlayerNode, run: Int, pass: Int) {
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        pendingBuffers += 1
        scheduledSamples += Int64(samples.count)
        node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isCurrent(run, pass) else { return }
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
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            MainActor.assumeIsolated { self.updateLocalProgress() }
        }
    }

    /// Characters played so far, from samples played: the rate measured on finished passages, or about 14
    /// characters a second until one has finished. (Sample time is before the speed change, so speed doesn't skew it.)
    private func updateLocalProgress() {
        guard state == .speaking, let node = playerNode, let nodeTime = node.lastRenderTime,
              let playerTime = node.playerTime(forNodeTime: nodeTime), totalChars > 0 else { return }
        let samplesPerChar = scheduledChars > 0 && completedSamples > 0
            ? Double(completedSamples) / Double(scheduledChars) : sampleRate / 14
        let chars = Double(max(0, playerTime.sampleTime)) / samplesPerChar
        setPassFraction(min(1, chars / Double(totalChars)))
    }

    /// Where the voice is within the current pass (0…1) → its offset in the whole text, and overall progress.
    private func setPassFraction(_ fraction: Double) {
        let remaining = max(0, textLength - base)
        let new = base + Int(fraction * Double(remaining))
        // Never backwards within a pass: estimates wobble.
        if new > position || position < base { position = new }
        progress = Double(position) / Double(max(textLength, 1))
    }

    private func teardownLocal() {
        playerNode?.stop()
        audioEngine?.stop()
        playerNode = nil
        audioEngine = nil
        timePitch = nil
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

    // MARK: - Read-along and speed

    private func begin(_ text: String, rate: Float, engine: Engine) {
        self.text = text
        self.engine = engine
        self.rate = rate
        textLength = (text as NSString).length
        sentences = Self.sentences(of: text)
        position = 0
        systemBase = 0
        systemRestartPending = false
    }

    #if SNAPSHOTS
    func setPreview(text: String, at sentence: Int, rate: Float) {
        begin(text, rate: rate, engine: .none)
        position = (sentences[safe: sentence]?.start ?? 0) + 30  // mid-sentence, for the word cursor
        voiceLabel = "Alba · Pocket TTS"
    }
    #endif

    /// Jumps to a sentence (a click in the read-along card); reading carries on from there, unpaused.
    func seek(toSentence index: Int) {
        guard let sentence = sentences[safe: index], state != .idle else { return }
        position = sentence.start
        progress = Double(position) / Double(max(textLength, 1))
        switch engine {
        case .system:
            systemRestartPending = false
            state = .speaking
            speakSystem(from: sentence.start)
        case .cloud, .local:
            // End this pass; the speak call's loop starts the next one at the target.
            seekTarget = sentence.start
            pass += 1
            player?.stop()
            player = nil
            fetches.values.forEach { $0.cancel() }
            fetches.removeAll()
            segmentDone?.resume()
            segmentDone = nil
            playerNode?.stop()
            pendingBuffers = 0
            drained?.resume()
            drained = nil
            state = .loading
        case .none:
            break
        }
    }

    /// Changes the speed of what's playing now (0.6–2×, in tenths). Not saved to the track.
    func setRate(_ value: Float) {
        let new = (min(2, max(0.6, value)) * 10).rounded() / 10
        guard new != rate else { return }
        rate = new
        switch engine {
        case .local:
            timePitch?.rate = new
        case .cloud:
            playbackRate = new
            player?.rate = new
        case .system:
            if state == .paused { systemRestartPending = true } else if state == .speaking { speakSystem(from: position) }
        case .none:
            break
        }
    }

    /// Speaks `text` from a UTF-16 offset (the start, or the word being spoken when the speed changes).
    private func speakSystem(from offset: Int) {
        let all = text as NSString
        let from = min(max(0, offset), all.length)
        currentUtterance = nil
        if synthesizer.isSpeaking || synthesizer.isPaused { synthesizer.stopSpeaking(at: .immediate) }
        guard from < all.length else { return finishPlayback() }
        systemBase = from
        let utterance = AVSpeechUtterance(string: all.substring(from: from))
        utterance.voice = systemVoice
        utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * rate)
        currentUtterance = utterance
        synthesizer.speak(utterance)
    }

    /// Sentences with their offsets, for the read-along card.
    static func sentences(of text: String) -> [Sentence] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var result: [Sentence] = []
        // A sentence token carries the whitespace after it, so a line break there opens the next paragraph.
        var breakBefore = false
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let raw = text[range]
            let piece = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty {
                let leading = raw.prefix { $0.isWhitespace }.contains { $0.isNewline }
                let start = raw.firstIndex { !$0.isWhitespace } ?? range.lowerBound
                result.append(Sentence(id: result.count, start: NSRange(start..<range.upperBound, in: text).location, text: piece,
                                       opensParagraph: !result.isEmpty && (breakBefore || leading)))
                breakBefore = raw.reversed().prefix { $0.isWhitespace }.contains { $0.isNewline }
            }
            return true
        }
        return result
    }

    // MARK: - Controls

    func togglePause() {
        switch state {
        case .speaking:
            if let playerNode { playerNode.pause() } else if let player { player.pause() } else { synthesizer.pauseSpeaking(at: .word) }
            state = .paused
        case .paused:
            if let playerNode {
                playerNode.play()
            } else if let player {
                player.play()
            } else if systemRestartPending {
                systemRestartPending = false
                speakSystem(from: position)  // the speed changed while paused
            } else {
                synthesizer.continueSpeaking()
            }
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
        seekTarget = nil
        currentUtterance = nil
        engine = .none
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
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            MainActor.assumeIsolated { self.updateCloudProgress() }
        }
    }

    private func updateCloudProgress() {
        guard state == .speaking, segments.indices.contains(segmentIndex), let player else { return }
        let total = segments.reduce(0) { $0 + $1.count }
        let done = segments.prefix(segmentIndex).reduce(0) { $0 + $1.count }
        let fraction = player.duration > 0 ? player.currentTime / player.duration : 0
        setPassFraction((Double(done) + fraction * Double(segments[segmentIndex].count)) / Double(max(total, 1)))
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
            guard utterance === self.currentUtterance else { return }
            self.position = self.systemBase + range.location
            self.progress = Double(self.systemBase + range.location + range.length) / Double(max(self.textLength, 1))
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            // Not one stopped for a speed change.
            guard utterance === self.currentUtterance else { return }
            self.finishPlayback()
        }
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
