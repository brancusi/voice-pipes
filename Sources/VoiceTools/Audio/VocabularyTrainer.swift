import AppKit
import Foundation

/// Finds the ways transcription mishears a word. Parakeet gives the same text for the same audio, so variety comes
/// from the audio: each of your recorded takes is replayed at different speeds, volumes and noise levels, and
/// (optionally) on-device voices say the word too. Every variation is transcribed and the distinct results counted.
struct VocabularyTrainer {
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
    }

    let parakeet: ParakeetService
    let spelling: String

    /// Runs every variation. `progress` gets (done, total) on the main actor.
    func run(takes: [[Float]], useVoices: Bool, progress: @escaping @MainActor (Int, Int) -> Void) async -> Report {
        var clips: [(samples: [Float], fromYou: Bool)] = []
        for take in takes {
            for variant in Self.variations(of: take) { clips.append((variant, true)) }
        }
        let voiceJobs: [(LocalVoiceEngine, String, Float)] = useVoices
            ? LocalVoiceEngine.allCases.flatMap { engine in
                engine.voices.flatMap { voice in [Float(1.0), 1.25].map { (engine, voice, $0) } }
            }
            : []

        let total = clips.count + voiceJobs.count
        var heard: [String: (you: Int, voices: Int)] = [:]
        var correct = 0, done = 0
        let target = Self.normalize(spelling)

        func record(_ text: String, fromYou: Bool) {
            let key = Self.normalize(text)
            guard !key.isEmpty else { return }
            if key == target { correct += 1; return }
            var entry = heard[key] ?? (0, 0)
            if fromYou { entry.you += 1 } else { entry.voices += 1 }
            heard[key] = entry
        }

        for clip in clips {
            if let text = try? await parakeet.transcribe(clip.samples) { record(text, fromYou: true) }
            done += 1
            await progress(done, total)
        }
        for (engine, voice, speed) in voiceJobs {
            if let samples = await Self.synthesize(spelling, engine: engine, voice: voice, speed: speed),
               let text = try? await parakeet.transcribe(samples) {
                record(text, fromYou: false)
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
        return Report(results: results, correct: correct, total: done)
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

    /// The word spoken by an on-device voice, as 16 kHz audio for Parakeet.
    private static func synthesize(_ text: String, engine: LocalVoiceEngine, voice: String, speed: Float) async -> [Float]? {
        guard let stream = try? await LocalVoices.shared.stream(engine, text: text, voice: voice) else { return nil }
        var samples: [Float] = []
        do {
            for try await chunk in stream { samples += chunk }
        } catch {
            return nil
        }
        return resample(samples, by: speed, from: LocalVoices.sampleRate(engine), to: 16_000)
    }

    // MARK: - Text

    static func normalize(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'-")).inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    @MainActor
    static func isAllDictionaryWords(_ text: String) -> Bool {
        let checker = NSSpellChecker.shared
        return text.split(separator: " ").allSatisfy { word in
            checker.checkSpelling(of: String(word), startingAt: 0).location == NSNotFound
        }
    }
}
