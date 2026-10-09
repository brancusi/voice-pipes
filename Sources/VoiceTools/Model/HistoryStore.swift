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
    /// The microphone the take recorded from, by name (runs from 1.17.0 on that started with a microphone).
    var microphone: String?
    /// The app in front when the run started: where a dictation went (runs from 1.17.0 on).
    var app: String?
    /// How long you spoke (runs from 1.17.0 on that started with a microphone).
    var spokenMs: Int?

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
        /// The model as the pickers name it ("local:pocket", "local:parakeet", or an OpenRouter id), for measured speeds.
        var model: String?
        /// Speak steps: how long until the first sound.
        var firstSoundMs: Int?
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

/// Every run, kept on disk for good (`HistoryDatabase`, history.sqlite) so a dictation that went nowhere — focus
/// moved, paste failed — can be found and copied again, even years later. Only the newest runs stay in memory
/// (`recent`); History's page, search and the model pickers' measurements query the database.
@MainActor
@Observable
final class HistoryStore {
    /// How many of the newest runs stay in memory.
    static let recentLimit = 200

    /// The newest runs, newest first.
    private(set) var recent: [RunRecord] = []
    /// Every run on disk.
    private(set) var count = 0
    /// Goes up whenever History changes, so pages that queried it ask again.
    private(set) var revision = 0
    @ObservationIgnored let database: HistoryDatabase?
    @ObservationIgnored private var weekCache: (revision: Int, at: Date, runs: [RunRecord])?

    init(url: URL = HistoryDatabase.defaultURL, legacyJSON: URL? = HistoryDatabase.legacyURL) {
        do {
            database = try HistoryDatabase(url: url, legacyJSON: legacyJSON)
        } catch {
            NSLog("VoiceTools: history unavailable: \(error)")
            database = nil
        }
        reload()
    }

    func add(_ record: RunRecord) {
        do { try database?.insert(record) } catch { NSLog("VoiceTools: couldn't save a run to history: \(error)") }
        recent.insert(record, at: 0)
        if recent.count > Self.recentLimit { recent.removeLast(recent.count - Self.recentLimit) }
        count += 1
        revision += 1
    }

    func clear() {
        try? database?.clear()
        reload()
    }

    /// Re-reads the newest runs and the count (another process, `vp`, never writes history, so only at launch).
    private func reload() {
        recent = database?.runs(limit: Self.recentLimit).map(\.record) ?? []
        count = database?.count() ?? 0
        revision += 1
    }

    /// Runs from the last 7 days (History's totals strip), cached until History changes or a minute passes.
    var lastWeek: [RunRecord] {
        if let cache = weekCache, cache.revision == revision, Date().timeIntervalSince(cache.at) < 60 { return cache.runs }
        let runs = database?.runs(since: Date().addingTimeInterval(-7 * 86_400)) ?? []
        weekCache = (revision, Date(), runs)
        return runs
    }
}
