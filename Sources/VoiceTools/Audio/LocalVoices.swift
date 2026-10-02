import FluidAudio
import Foundation

/// Runs the on-device text-to-speech engines. Each engine downloads its model once and loads on first use
/// (or at launch when a track uses it); after that, speech never leaves the Mac.
actor LocalVoices {
    static let shared = LocalVoices()

    enum State: Equatable { case notLoaded, loading, ready, failed(String) }

    private var pocket: PocketTtsManager?
    private var supertonic: Supertonic3Manager?
    private var loads: [LocalVoiceEngine: Task<Void, Error>] = [:]
    private var supertonicStyles: [String: Supertonic3VoiceStyle] = [:]
    private(set) var states: [LocalVoiceEngine: State] = [:]

    /// Called on the main actor whenever an engine's state changes.
    private var onChange: (@Sendable (LocalVoiceEngine, State) -> Void)?

    func observe(_ handler: @escaping @Sendable (LocalVoiceEngine, State) -> Void) {
        onChange = handler
    }

    func state(_ engine: LocalVoiceEngine) -> State { states[engine] ?? .notLoaded }

    /// Downloads (first time only) and loads the engine. Concurrent callers share one load.
    func prepare(_ engine: LocalVoiceEngine) async throws {
        if let load = loads[engine] { return try await load.value }
        let load = Task { try await performLoad(engine) }
        loads[engine] = load
        do {
            try await load.value
        } catch {
            loads[engine] = nil // allow a retry
            throw error
        }
    }

    private func performLoad(_ engine: LocalVoiceEngine) async throws {
        set(engine, .loading)
        await MainActor.run { ModelDownloads.shared.track(.init(engine)) }
        defer { Task { @MainActor in ModelDownloads.shared.finish(.init(engine)) } }
        do {
            switch engine {
            case .pocket:
                let manager = PocketTtsManager()
                try await manager.initialize()
                pocket = manager
            case .supertonic:
                supertonic = try await Supertonic3Manager.downloadAndCreate()
            }
            set(engine, .ready)
        } catch {
            set(engine, .failed(error.localizedDescription))
            throw error
        }
    }

    private func set(_ engine: LocalVoiceEngine, _ state: State) {
        states[engine] = state
        onChange?(engine, state)
    }

    nonisolated static func sampleRate(_ engine: LocalVoiceEngine) -> Double {
        switch engine {
        case .pocket: 24_000
        case .supertonic: Double(Supertonic3Constants.sampleRate)
        }
    }

    /// Audio for one passage, as it's generated: Pocket TTS yields ~80 ms frames, Supertonic the whole passage.
    func stream(_ engine: LocalVoiceEngine, text: String, voice: String) async throws -> AsyncThrowingStream<[Float], Error> {
        try await prepare(engine)
        switch engine {
        case .pocket:
            guard let pocket else { throw LocalVoiceError.notLoaded(engine) }
            let frames = try await pocket.synthesizeStreaming(text: text, voice: voice)
            return AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        for try await frame in frames { continuation.yield(frame.samples) }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        case .supertonic:
            guard let supertonic else { throw LocalVoiceError.notLoaded(engine) }
            let style = try await supertonicStyle(voice)
            let samples = try await supertonic.synthesize(text: text, language: "en", style: style).samples
            return AsyncThrowingStream { continuation in
                continuation.yield(samples)
                continuation.finish()
            }
        }
    }

    /// Supertonic voices are small JSON files fetched once from the model's repository and kept with the app's data.
    private func supertonicStyle(_ voice: String) async throws -> Supertonic3VoiceStyle {
        if let style = supertonicStyles[voice] { return style }
        guard LocalVoiceEngine.supertonic.voices.contains(voice) else { throw LocalVoiceError.unknownVoice(voice) }
        let dir = TrackStore.defaultURL.deletingLastPathComponent().appendingPathComponent("supertonic-voices", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("\(voice).json")
        if !FileManager.default.fileExists(atPath: file.path) {
            let url = URL(string: "https://huggingface.co/FluidInference/supertonic-3-coreml/resolve/main/voice_styles/\(voice).json")!
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw LocalVoiceError.voiceDownloadFailed(voice) }
            try data.write(to: file, options: .atomic)
        }
        let style = try Supertonic3VoiceStyle.load(from: file)
        supertonicStyles[voice] = style
        return style
    }
}

enum LocalVoiceError: LocalizedError {
    case notLoaded(LocalVoiceEngine)
    case unknownVoice(String)
    case voiceDownloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .notLoaded(let engine): "\(engine.label) isn't loaded."
        case .unknownVoice(let voice): "Unknown voice: \(voice)"
        case .voiceDownloadFailed(let voice): "Couldn't download the Supertonic voice \(voice)."
        }
    }
}
