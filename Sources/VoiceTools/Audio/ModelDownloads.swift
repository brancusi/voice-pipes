import FluidAudio
import Foundation
import Observation

/// Download progress for the on-device models, measured as bytes on disk. FluidAudio streams every file into
/// `<file>.partial` inside the model's folder, so the folder grows smoothly; its own progress callbacks restart
/// for each internal step (download, then compile, then each sub-model), which made a bar jump back and blink.
/// Here the fraction only ever moves forward, and once the bytes are in, the model is "preparing" (compiling).
@MainActor
@Observable
final class ModelDownloads {
    static let shared = ModelDownloads()

    enum Model: String, CaseIterable {
        case parakeet, pocket, supertonic

        /// What a full download weighs (measured from FluidAudio's folders), the bar's 100%.
        var totalBytes: Int64 {
            switch self {
            case .parakeet: 483_257_242
            case .pocket: 529_604_738
            case .supertonic: 168_688_140
            }
        }

        /// The folder FluidAudio downloads it into.
        var folder: URL {
            let home = FileManager.default.homeDirectoryForCurrentUser
            switch self {
            case .parakeet: return AsrModels.defaultCacheDirectory(for: .v3)
            case .pocket: return home.appendingPathComponent(".cache/fluidaudio/Models/pocket-tts", isDirectory: true)
            case .supertonic: return home.appendingPathComponent(".cache/fluidaudio/Models/supertonic-3", isDirectory: true)
            }
        }

        init(_ engine: LocalVoiceEngine) {
            switch engine {
            case .pocket: self = .pocket
            case .supertonic: self = .supertonic
            }
        }
    }

    struct Status: Equatable {
        /// 0…1, never backwards.
        var fraction: Double = 0
        var bytes: Int64 = 0
        var total: Int64
        /// Recent download speed, bytes a second.
        var rate: Double = 0
        /// Downloaded (or already there); now compiling and loading.
        var preparing = false
        /// Not growing, well short of done: the network is slow or retrying.
        var waiting = false

        /// "212 / 483 MB · 11 MB/s", or "preparing for this Mac…".
        var label: String {
            if preparing { return "preparing for this Mac…" }
            let mb = { (b: Int64) in Int((Double(b) / 1_000_000).rounded()) }
            let speed = waiting ? " · waiting for the network…" : rate >= 50_000 ? String(format: " · %.0f MB/s", max(1, rate / 1_000_000)) : ""
            return "\(mb(bytes)) / \(mb(total)) MB" + speed
        }
    }

    private(set) var status: [Model: Status] = [:]
    @ObservationIgnored private var tasks: [Model: Task<Void, Never>] = [:]

    /// Starts measuring while `model` loads; `finish` stops and clears it.
    func track(_ model: Model) {
        guard tasks[model] == nil else { return }
        status[model] = Status(total: model.totalBytes)
        tasks[model] = Task { [weak self] in
            var samples: [(Date, Int64)] = []
            var unchangedSince = Date()
            while !Task.isCancelled {
                let bytes = await Task.detached(priority: .utility) { Self.size(of: model.folder) }.value
                guard let self, var current = self.status[model] else { return }
                let now = Date()
                if bytes != current.bytes { unchangedSince = now }
                samples.append((now, bytes))
                samples.removeAll { now.timeIntervalSince($0.0) > 3 }
                if let first = samples.first, now.timeIntervalSince(first.0) > 0.5 {
                    current.rate = Double(bytes - first.1) / now.timeIntervalSince(first.0)
                }
                current.bytes = max(current.bytes, bytes)
                current.fraction = max(current.fraction, min(0.99, Double(current.bytes) / Double(model.totalBytes)))
                // No longer growing: near the end (sizes vary a little by version) it's compiling for this Mac;
                // earlier, it's waiting on the network (FluidAudio retries stalled downloads itself).
                let still = now.timeIntervalSince(unchangedSince) > 1.5
                current.preparing = current.fraction >= 0.9 && still
                current.waiting = !current.preparing && still && current.bytes > 0
                if current.preparing { current.fraction = max(current.fraction, 0.99) }
                if current != self.status[model] { self.status[model] = current }
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
    }

    func finish(_ model: Model) {
        tasks[model]?.cancel()
        tasks[model] = nil
        status[model] = nil
    }

    /// Bytes of every file under `url`, partial downloads included.
    nonisolated static func size(of url: URL) -> Int64 {
        guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in walker {
            guard let values = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]), values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }
}
