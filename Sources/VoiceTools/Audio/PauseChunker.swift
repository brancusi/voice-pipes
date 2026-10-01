import Foundation

/// Splits a live 16 kHz stream into phrases at natural pauses, so each phrase can be
/// transcribed while the user is still talking. Pure logic: feed samples, get chunks back.
struct PauseChunker {
    var pauseMs: Int
    /// Don't cut before this much audio has accumulated.
    var minChunkSeconds: Double = 1.0
    /// Force a cut before Parakeet's ~15 s single-window limit.
    var maxChunkSeconds: Double = 14.0

    private let sampleRate = 16_000
    private let frameSize = 320 // 20 ms
    private var pending: [Float] = []
    private var current: [Float] = []
    private var silentFrames = 0
    private var heardSpeech = false
    private var noiseFloor: Float = 0.003

    init(pauseMs: Int) { self.pauseMs = pauseMs }

    /// Feeds samples; returns any chunks that completed.
    mutating func feed(_ samples: [Float]) -> [[Float]] {
        pending.append(contentsOf: samples)
        var chunks: [[Float]] = []
        while pending.count >= frameSize {
            let frame = Array(pending.prefix(frameSize))
            pending.removeFirst(frameSize)
            if let chunk = consume(frame) { chunks.append(chunk) }
        }
        return chunks
    }

    /// Returns whatever is left once capture stops.
    mutating func flush() -> [Float]? {
        current.append(contentsOf: pending)
        pending.removeAll()
        defer { current.removeAll(); heardSpeech = false; silentFrames = 0 }
        return heardSpeech ? current : nil
    }

    private mutating func consume(_ frame: [Float]) -> [Float]? {
        current.append(contentsOf: frame)
        let rms = sqrt(frame.reduce(0) { $0 + $1 * $1 } / Float(frame.count))
        let isSilent = rms < max(0.006, noiseFloor * 3)

        if isSilent {
            silentFrames += 1
            // Track background noise slowly so the threshold adapts to the room and mic gain.
            noiseFloor = noiseFloor * 0.95 + rms * 0.05
        } else {
            silentFrames = 0
            heardSpeech = true
        }

        let seconds = Double(current.count) / Double(sampleRate)
        let pauseFrames = pauseMs / 20
        let longPause = heardSpeech && silentFrames >= pauseFrames && seconds >= minChunkSeconds
        guard longPause || seconds >= maxChunkSeconds else { return nil }

        // Cut in the middle of the silence so neither side loses a word edge.
        let keep = longPause ? (silentFrames / 2) * frameSize : 0
        let chunk = Array(current.dropLast(keep))
        current = Array(current.suffix(keep))
        let hadSpeech = heardSpeech
        heardSpeech = false
        silentFrames = 0
        return hadSpeech ? chunk : nil
    }
}
