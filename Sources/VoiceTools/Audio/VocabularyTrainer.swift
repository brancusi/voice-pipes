import AppKit
@preconcurrency import AVFoundation
import Foundation

/// Finds the ways transcription mishears a word. Parakeet gives the same text for the same audio, so variety comes
/// from the audio: each of your recorded takes is replayed at different speeds, volumes and noise levels, and
/// (optionally) on-device and macOS voices say it too. Every variation is transcribed and the distinct results counted.
///
/// Takes are sentences with the word in them, and only the part of the transcript where the word was is kept: said on
/// its own, a word gets misheard in ways real dictation never produces (Parakeet is multilingual, and a lone word
/// often comes back in another language). Measured 2026-10-05 on seven terms × 42 voices: sentences found the
/// mishearings from real dictation as well as lone words did, with far fewer stray ones (docs/research.md).
struct VocabularyTrainer {
    /// One recorded take and the sentence that was read.
    struct Take {
        var samples: [Float]
        var sentence: String
    }

    /// Built-in sentences, when none were written for the word (`TrainingSentences`): the word in different places.
    /// `{w}` is the word.
    static let carriers = [
        "I had a quick chat with {w} today.",
        "Can you look at {w} for me?",
        "{w} is next on my list.",
        "We talked about {w} again this morning.",
        "Let's ask {w} about it tomorrow.",
        "I still need to check {w} before Friday.",
    ]

    /// The built-in sentences for a word.
    static func builtInSentences(_ word: String) -> [String] {
        carriers.map { $0.replacingOccurrences(of: "{w}", with: word) }
    }

    struct Result: Identifiable, Hashable {
        var id: String { text }
        /// As heard, lowercased (matching ignores case anyway).
        let text: String
        var count: Int
        var fromYou: Int
        var fromVoices: Int
        /// Every word is an ordinary dictionary word, so replacing it could also change text you meant literally.
        let commonWords: Bool
    }

    struct Report {
        var results: [Result]
        /// Transcriptions that already matched the spelling.
        var correct: Int
        var total: Int
        /// Transcriptions set aside: the words around the term were misheard or misread too, so the part that's the
        /// term couldn't be told apart (`SpanAligner`).
        var setAside = 0
    }

    let parakeet: ParakeetService
    let spelling: String

    /// A voice that can say a sentence: an on-device one, or a macOS one.
    private enum Voice {
        case local(LocalVoiceEngine, String)
        case macos(AVSpeechSynthesisVoice)
    }

    /// Runs every variation. `progress` gets (done, total) on the main actor.
    /// `sentences`: what the voices read (the same ones the user reads), two each.
    func run(takes: [Take], sentences: [String], useVoices: Bool, progress: @escaping @MainActor (Int, Int) -> Void) async -> Report {
        let sentences = sentences.isEmpty ? Self.builtInSentences(spelling) : sentences
        var clips: [(samples: [Float], sentence: String)] = []
        for take in takes {
            for variant in Self.variations(of: take.samples) { clips.append((variant, take.sentence)) }
        }
        var voices: [Voice] = []
        if useVoices {
            voices = LocalVoiceEngine.allCases.flatMap { engine in engine.voices.map { Voice.local(engine, $0) } }
            voices += await MainActor.run { Self.macVoices().map(Voice.macos) }
        }
        // Each voice reads two of the sentences.
        let voiceJobs = voices.enumerated().flatMap { i, voice in
            [(voice, sentences[(2 * i) % sentences.count]), (voice, sentences[(2 * i + 1) % sentences.count])]
        }

        let total = clips.count + voiceJobs.count
        var heard: [String: (you: Int, voices: Int)] = [:]
        var correct = 0, done = 0, setAside = 0
        let target = Self.normalize(spelling)
        let latinTarget = !Self.hasOtherScript(target)

        func record(_ transcript: String, sentence: String, fromYou: Bool) {
            let key: String
            switch SpanAligner.span(of: spelling, in: transcript, sentence: sentence, normalize: Self.normalize) {
            case .correct: correct += 1; return
            case .rejected: setAside += 1; return
            case .heard(let heard): key = heard
            }
            if key == target { correct += 1; return }
            // A Latin word heard as Cyrillic, Greek and the like: the model guessing another language, not a mishearing.
            if latinTarget, Self.hasOtherScript(key) { return }
            var entry = heard[key] ?? (0, 0)
            if fromYou { entry.you += 1 } else { entry.voices += 1 }
            heard[key] = entry
        }

        for clip in clips {
            if let text = try? await parakeet.transcribe(clip.samples) { record(text, sentence: clip.sentence, fromYou: true) }
            done += 1
            await progress(done, total)
        }
        for (voice, sentence) in voiceJobs {
            let samples: [Float]?
            switch voice {
            case .local(let engine, let name): samples = await Self.synthesize(sentence, engine: engine, voice: name)
            case .macos(let v): samples = await Self.synthesizeMac(sentence, voice: v)
            }
            if let samples, let text = try? await parakeet.transcribe(samples) {
                record(text, sentence: sentence, fromYou: false)
            }
            done += 1
            await progress(done, total)
        }

        let counts = heard
        let results = await MainActor.run {
            counts.map { text, counts in
                Result(text: text, count: counts.you + counts.voices, fromYou: counts.you, fromVoices: counts.voices,
                       commonWords: Self.isAllDictionaryWords(text))
            }
            .sorted { ($0.fromYou, $0.count) > ($1.fromYou, $1.count) }
        }
        return Report(results: results, correct: correct, total: done, setAside: setAside)
    }

    // MARK: - Audio variations

    /// About 30 versions of one take: 5 speeds × 2 volumes × 3 noise levels, half with a short lead-in pause.
    static func variations(of take: [Float]) -> [[Float]] {
        var out: [[Float]] = []
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        for (i, speed) in [Float(0.85), 0.93, 1.0, 1.08, 1.17].enumerated() {
            let resampled = resample(take, by: speed)
            for (j, gain) in [Float(0.45), 1.0].enumerated() {
                for (k, noise) in [Float(0), 0.004, 0.012].enumerated() {
                    var clip = resampled.map { $0 * gain }
                    if noise > 0 {
                        for n in clip.indices {
                            seed = seed &* 6364136223846793005 &+ 1442695040888963407
                            clip[n] += (Float(seed >> 40) / Float(1 << 24) - 0.5) * 2 * noise
                        }
                    }
                    if (i + j + k) % 2 == 1 { clip = Array(repeating: 0, count: 4_800) + clip } // 0.3 s lead-in
                    out.append(clip)
                }
            }
        }
        return out
    }

    /// Plays audio faster (>1) or slower (<1) by linear interpolation; pitch shifts with it, like a different voice.
    static func resample(_ samples: [Float], by factor: Float, from inputRate: Double = 16_000, to outputRate: Double = 16_000) -> [Float] {
        guard !samples.isEmpty else { return [] }
        let step = Double(factor) * inputRate / outputRate
        let count = Int(Double(samples.count) / step)
        guard count > 1 else { return samples }
        return (0..<count).map { i in
            let position = Double(i) * step
            let index = Int(position)
            let next = min(index + 1, samples.count - 1)
            let t = Float(position - Double(index))
            return samples[index] * (1 - t) + samples[next] * t
        }
    }

    /// A sentence spoken by an on-device voice, as 16 kHz audio for Parakeet.
    private static func synthesize(_ text: String, engine: LocalVoiceEngine, voice: String) async -> [Float]? {
        guard let stream = try? await LocalVoices.shared.stream(engine, text: text, voice: voice) else { return nil }
        var samples: [Float] = []
        do {
            for try await chunk in stream { samples += chunk }
        } catch {
            return nil
        }
        return resample(samples, by: 1, from: LocalVoices.sampleRate(engine), to: 16_000)
    }

    /// The Mac's English voices, one per name (the best quality installed of each).
    @MainActor static func macVoices() -> [AVSpeechSynthesisVoice] {
        var seen = Set<String>()
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") && !$0.identifier.contains("eloquence") && !$0.identifier.contains("speech.synthesis.voice") }
            .sorted { $0.quality.rawValue > $1.quality.rawValue }
            .filter { seen.insert($0.name).inserted }
    }

    @MainActor private static let synthesizer = AVSpeechSynthesizer()

    /// A sentence spoken by a macOS voice, as 16 kHz audio for Parakeet.
    @MainActor private static func synthesizeMac(_ text: String, voice: AVSpeechSynthesisVoice) async -> [Float]? {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        return await withCheckedContinuation { (done: CheckedContinuation<[Float]?, Never>) in
            var samples: [Float] = []
            var rate: Double = 22_050
            var resumed = false
            synthesizer.write(utterance) { buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer else { return }
                if pcm.frameLength == 0 {
                    // The last (empty) buffer: done.
                    guard !resumed else { return }
                    resumed = true
                    done.resume(returning: samples.isEmpty ? nil : resample(samples, by: 1, from: rate, to: 16_000))
                    return
                }
                rate = pcm.format.sampleRate
                if let f = pcm.floatChannelData {
                    samples += UnsafeBufferPointer(start: f[0], count: Int(pcm.frameLength))
                } else if let i = pcm.int16ChannelData {
                    samples += UnsafeBufferPointer(start: i[0], count: Int(pcm.frameLength)).map { Float($0) / 32_768 }
                }
            }
        }
    }

    // MARK: - Text

    /// Letters outside Latin (Cyrillic, Greek, CJK…).
    static func hasOtherScript(_ text: String) -> Bool {
        text.unicodeScalars.contains { $0.properties.isAlphabetic && $0.value > 0x024F }
    }

    static func normalize(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'-")).inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    @MainActor
    static func isAllDictionaryWords(_ text: String) -> Bool {
        // English only: with the Mac's languages on "automatic", "claro" and "waar" pass as Spanish and Dutch.
        let checker = NSSpellChecker.shared
        return text.split(separator: " ").allSatisfy { word in
            var count = 0
            return checker.checkSpelling(of: String(word), startingAt: 0, language: "en", wrap: false,
                                         inSpellDocumentWithTag: 0, wordCount: &count).location == NSNotFound
        }
    }
}
