import Foundation

/// Splits a live 16 kHz stream into phrases at natural pauses, so each phrase can be
/// transcribed while the user is still talking. Pure logic: feed samples, get chunks back.
///
/// Every sample ends up in exactly one chunk, except chunks that are near digital silence throughout.
struct PauseChunker {
    var pauseMs: Int
    /// Don't cut before this much audio: Parakeet is noticeably less accurate on very short clips.
    var minChunkSeconds: Double = 3.0
    /// Force a cut before Parakeet's ~15 s single-window limit.
    var maxChunkSeconds: Double = 14.0

    private let sampleRate = 16_000
    private let frameSize = 320 // 20 ms
    /// A chunk whose loudest frame is below this is treated as empty (mic muted, room noise only).
    private let silenceFloor: Float = 0.003
    private var pending: [Float] = []
    private var current: [Float] = []
    private var silentFrames = 0
    private var chunkPeak: Float = 0
    /// Levels of the last 3 s of frames. The pause threshold comes from these, so it follows the room
    /// and the mic gain without drifting: a fixed window can't be dragged upward by long stretches of speech.
    private var recentLevels: [Float] = []
    private let windowFrames = 150
    private(set) var pauseThreshold: Float = 0.006

    init(pauseMs: Int) { self.pauseMs = pauseMs }

    /// Feeds samples; returns any chunks that completed.
    mutating func feed(_ samples: [Float]) -> [[Float]] {
        pending.append(contentsOf: samples)
        var chunks: [[Float]] = []
        var offset = 0
        while pending.count - offset >= frameSize {
            let frame = Array(pending[offset..<offset + frameSize])
            offset += frameSize
            if let chunk = consume(frame) { chunks.append(chunk) }
        }
        pending.removeFirst(offset)
        return chunks
    }

    /// Returns whatever is left once capture stops.
    mutating func flush() -> [Float]? {
        current.append(contentsOf: pending)
        pending.removeAll()
        let peak = max(chunkPeak, rms(current))
        defer { current.removeAll(); chunkPeak = 0; silentFrames = 0 }
        return peak >= silenceFloor && !current.isEmpty ? current : nil
    }

    private mutating func consume(_ frame: [Float]) -> [Float]? {
        current.append(contentsOf: frame)
        let level = rms(frame)
        chunkPeak = max(chunkPeak, level)

        updateThreshold(with: level)
        silentFrames = level < pauseThreshold ? silentFrames + 1 : 0

        let seconds = Double(current.count) / Double(sampleRate)
        let longPause = silentFrames >= pauseMs / 20 && seconds >= minChunkSeconds
        guard longPause || seconds >= maxChunkSeconds else { return nil }

        // Cut in the middle of the pause so neither side loses a word edge.
        let keep = longPause ? (silentFrames / 2) * frameSize : 0
        let chunk = Array(current.dropLast(keep))
        current = Array(current.suffix(keep))
        let peak = chunkPeak
        chunkPeak = 0
        silentFrames = 0
        return peak >= silenceFloor ? chunk : nil
    }

    /// A pause is clearly above the background (10th percentile) but clearly below speech (90th percentile).
    private mutating func updateThreshold(with level: Float) {
        recentLevels.append(level)
        if recentLevels.count > windowFrames { recentLevels.removeFirst() }
        guard recentLevels.count >= 25 else { return }
        let sorted = recentLevels.sorted()
        let background = sorted[sorted.count / 10]
        let speech = sorted[sorted.count * 9 / 10]
        pauseThreshold = min(max(background * 2.5, 0.006), max(speech * 0.35, 0.004))
    }

    private func rms(_ samples: [Float]) -> Float {
        samples.isEmpty ? 0 : sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count))
    }
}
