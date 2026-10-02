@preconcurrency import AVFoundation
import FluidAudio
import Foundation

/// Owns the on-device Parakeet v3 model. Load once at launch; transcription is serialized by the actor.
actor ParakeetService {
    enum State: Equatable { case notLoaded, loading, ready, failed(String) }

    private var manager: AsrManager?
    private var models: AsrModels?
    private var loadTask: Task<Void, Never>?
    private(set) var state: State = .notLoaded

    /// Download progress (0…1) while the model is fetched the first time.
    private var onProgress: (@Sendable (Double) -> Void)?

    func setProgressHandler(_ handler: @escaping @Sendable (Double) -> Void) { onProgress = handler }

    /// Downloads (first run only) and loads the model. Concurrent callers share one load.
    func load() async {
        if loadTask == nil {
            loadTask = Task { await performLoad() }
        }
        await loadTask?.value
    }

    private func performLoad() async {
        state = .loading
        let report = onProgress
        do {
            let models = try await AsrModels.downloadAndLoad(version: .v3, progressHandler: { progress in
                report?(progress.fractionCompleted)
            })
            let manager = AsrManager(config: .default)
            try await manager.loadModels(models)
            self.manager = manager
            self.models = models
            state = .ready
        } catch {
            state = .failed(error.localizedDescription)
            report?(1) // clears the progress shown in setup; the failure is in `state`
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

    /// A sliding-window streaming session sharing the already-loaded models (no reload).
    func startStreamingSession() async throws -> SlidingWindowAsrManager {
        if models == nil { await load() }
        guard let models else { throw ParakeetError.notLoaded }
        let session = SlidingWindowAsrManager(config: .streaming)
        try await session.loadModels(models)
        try await session.startStreaming(source: .microphone)
        return session
    }
}

/// Transcribes while the user is still recording, so release only waits for the tail.
protocol LiveTranscriber: AnyObject, Sendable {
    func feed(_ samples: [Float])
    func finish() async throws -> String
    func cancel()
}

/// Feeds a live recording to a Parakeet sliding-window session, in order, and reports live text.
final class StreamingTranscriber: LiveTranscriber, @unchecked Sendable {
    private let input: AsyncStream<[Float]>.Continuation
    private let worker: Task<String, Error>

    init(parakeet: ParakeetService, onPartial: @escaping @Sendable (String) -> Void) {
        let (stream, continuation) = AsyncStream<[Float]>.makeStream()
        input = continuation
        worker = Task {
            let session = try await parakeet.startStreamingSession()
            let updates = Task {
                var confirmed = ""
                for await update in await session.transcriptionUpdates {
                    if update.isConfirmed {
                        confirmed = [confirmed, update.text].filter { !$0.isEmpty }.joined(separator: " ")
                        onPartial(confirmed)
                    } else {
                        onPartial([confirmed, update.text].filter { !$0.isEmpty }.joined(separator: " "))
                    }
                }
            }
            defer { updates.cancel() }
            // Audio recorded while the session was starting is buffered in the stream, so nothing is lost.
            for await samples in stream {
                if let buffer = Self.buffer(samples) { await session.streamAudio(buffer) }
            }
            return try await session.finish().trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// Audio-thread entry point.
    func feed(_ samples: [Float]) { input.yield(samples) }

    func finish() async throws -> String {
        input.finish()
        return try await worker.value
    }

    func cancel() {
        input.finish()
        worker.cancel()
    }

    private static let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1,
                                              interleaved: false)!

    private static func buffer(_ samples: [Float]) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        return buffer
    }
}

enum ParakeetError: LocalizedError {
    case notLoaded
    var errorDescription: String? { "Parakeet model is not loaded." }
}

/// Transcribes phrase chunks as they arrive during recording, in order, so that on release
/// only the final short chunk is left to process.
final class ChunkedTranscriber: LiveTranscriber, @unchecked Sendable {
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

    func cancel() {
        lock.withLock { tail.cancel() }
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
