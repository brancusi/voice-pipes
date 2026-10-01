import FluidAudio
import Foundation

/// Owns the on-device Parakeet v3 model. Load once at launch; transcription is serialized by the actor.
actor ParakeetService {
    enum State: Equatable { case notLoaded, loading, ready, failed(String) }

    private var manager: AsrManager?
    private var loadTask: Task<Void, Never>?
    private(set) var state: State = .notLoaded

    /// Downloads (first run only) and loads the model. Concurrent callers share one load.
    func load() async {
        if loadTask == nil {
            loadTask = Task { await performLoad() }
        }
        await loadTask?.value
    }

    private func performLoad() async {
        state = .loading
        do {
            let models = try await AsrModels.downloadAndLoad(version: .v3)
            let manager = AsrManager(config: .default)
            try await manager.loadModels(models)
            self.manager = manager
            state = .ready
        } catch {
            state = .failed(error.localizedDescription)
            loadTask = nil // allow a retry
        }
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        if manager == nil { await load() }
        guard let manager else { throw ParakeetError.notLoaded }
        // Parakeet needs ~1 s of context; pad very short clips with silence.
        let padded = samples.count < 16_000 ? samples + Array(repeating: 0, count: 16_000 - samples.count) : samples
        var state = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        return try await manager.transcribe(padded, decoderState: &state).text
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum ParakeetError: LocalizedError {
    case notLoaded
    var errorDescription: String? { "Parakeet model is not loaded." }
}

/// Transcribes phrase chunks as they arrive during recording, in order, so that on release
/// only the final short chunk is left to process.
final class ChunkedTranscriber: @unchecked Sendable {
    private let parakeet: ParakeetService
    private let lock = NSLock()
    private var chunker: PauseChunker
    private var tail: Task<[String], Never> = Task { [] }

    /// Called with the running transcript after each chunk completes.
    var onPartial: (@Sendable (String) -> Void)?

    init(parakeet: ParakeetService, pauseMs: Int) {
        self.parakeet = parakeet
        self.chunker = PauseChunker(pauseMs: pauseMs)
    }

    /// Audio-thread entry point.
    func feed(_ samples: [Float]) {
        let chunks = lock.withLock { chunker.feed(samples) }
        chunks.forEach(enqueue)
    }

    /// Flushes the last chunk and returns the full transcript.
    func finish() async -> String {
        if let last = lock.withLock({ chunker.flush() }) { enqueue(last) }
        let parts = await lock.withLock { tail }.value
        return parts.joined(separator: " ")
    }

    private func enqueue(_ chunk: [Float]) {
        lock.withLock {
            let previous = tail
            let parakeet = parakeet
            let onPartial = onPartial
            tail = Task {
                var parts = await previous.value
                if let text = try? await parakeet.transcribe(chunk), !text.isEmpty {
                    parts.append(text)
                    onPartial?(parts.joined(separator: " "))
                }
                return parts
            }
        }
    }
}
