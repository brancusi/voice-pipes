import Foundation
import Observation

/// One finished (or failed) run: what came out, so it can be copied again later.
struct RunRecord: Codable, Identifiable, Hashable {
    struct StepTiming: Codable, Hashable {
        let title: String
        let ms: Int
        /// The step's category (Input, Transcribe, Transform, Output), for colouring the chain. Missing in runs
        /// saved before 1.4.0.
        var category: String?
    }

    var id = UUID()
    let trackName: String
    /// The track's colour when it ran. Missing in runs saved before 1.4.0.
    var colorHex: String?
    let date: Date
    /// The run's final text (what was pasted, copied or read).
    let text: String
    let totalMs: Int
    var steps: [StepTiming] = []
    /// What transcription heard, when later steps changed it (a question before its answer, raw dictation before
    /// cleanup).
    var heard: String?
    /// Why the run stopped, if it failed; `text` is then the last text it had.
    var failure: String?
    /// Exactly how the run went, step by step (runs from 1.7.2 on; older runs have none).
    var log: [LogEntry]?

    /// One step as it ran: what went in and came out, how long it took, what it cost, and for a Branch or Route
    /// what Jev chose.
    struct LogEntry: Codable, Hashable {
        enum Status: String, Codable { case ok, failed, passedThrough }

        var title: String
        var category: String?
        /// 0 for the track's own steps, 1 inside a branch, 2 inside a branch in a branch…
        var depth: Int
        var ms: Int
        /// Text in and out (capped), or "audio · 4.2 s".
        var input: String?
        var output: String?
        var decision: Decision?
        var usage: Usage?
        var status: Status
        var message: String?
        /// A Speak step's voice, shown with its usage rather than in the title.
        var voice: String?
    }

    struct Decision: Codable, Hashable {
        /// "branch" or "route".
        var kind: String
        var question: String?
        var chosen: String
        var confidence: Double?
        var jevMs: Int
        /// The branches or routes not taken.
        var others: [String]
    }

    /// What a step's cloud calls used. Exact for LLMs and transcription (OpenRouter reports it); cloud speech is
    /// priced from the catalogue (`estimated`); on-device steps are `local`.
    struct Usage: Codable, Hashable {
        var model: String?
        var promptTokens: Int?
        var completionTokens: Int?
        var seconds: Double?
        var characters: Int?
        var cost: Double?
        var estimated: Bool?
        var local: Bool?

        mutating func add(_ other: Usage) {
            func sum<T: AdditiveArithmetic>(_ a: T?, _ b: T?) -> T? { a == nil && b == nil ? nil : (a ?? .zero) + (b ?? .zero) }
            model = other.model ?? model
            promptTokens = sum(promptTokens, other.promptTokens)
            completionTokens = sum(completionTokens, other.completionTokens)
            seconds = sum(seconds, other.seconds)
            characters = sum(characters, other.characters)
            cost = sum(cost, other.cost)
            if other.estimated == true { estimated = true }
            if other.local == true, cost == nil { local = true }
        }
    }

    /// The whole run's cloud use (nil for runs without a log, or that used nothing).
    var usageTotal: Usage? {
        let used = (log ?? []).compactMap(\.usage).filter { $0.local != true }
        guard !used.isEmpty else { return nil }
        var total = Usage()
        for u in used { total.add(u) }
        total.model = nil
        return total
    }
}

/// Collects what one step's cloud calls used. A task-local, so OpenRouterClient can report into whichever step
/// is calling it and concurrent runs never mix.
final class UsageMeter: @unchecked Sendable {
    @TaskLocal static var current: UsageMeter?
    private let lock = NSLock()
    private var usage: RunRecord.Usage?

    func add(_ part: RunRecord.Usage) {
        lock.lock(); defer { lock.unlock() }
        if usage == nil { usage = part } else { usage?.add(part) }
    }

    var total: RunRecord.Usage? {
        lock.lock(); defer { lock.unlock() }
        return usage
    }
}

/// Every run's text, kept on disk (`history.json` beside the tracks) so a dictation that went nowhere — focus
/// moved, paste failed — can be found and copied again, even after a restart.
@MainActor
@Observable
final class HistoryStore {
    static let limit = 1000
    nonisolated static let defaultURL = TrackStore.defaultURL.deletingLastPathComponent().appendingPathComponent("history.json")

    private(set) var records: [RunRecord] = []
    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private let writer = DispatchQueue(label: "VoiceTools.history")

    init(fileURL: URL = HistoryStore.defaultURL) {
        self.fileURL = fileURL
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            records = try JSONDecoder().decode([RunRecord].self, from: data)
        } catch {
            // Never overwrite history we can't read: keep it aside and start a new file.
            let backup = fileURL.deletingPathExtension()
                .appendingPathExtension("unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: fileURL, to: backup)
            NSLog("VoiceTools: couldn't read history (\(error)); moved it to \(backup.lastPathComponent)")
        }
    }

    func add(_ record: RunRecord) {
        records.insert(record, at: 0)
        if records.count > Self.limit { records.removeLast(records.count - Self.limit) }
        save()
    }

    func clear() {
        records = []
        save()
    }

    /// Writes off the main thread, in order, atomically.
    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        let url = fileURL
        writer.async {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }
}
