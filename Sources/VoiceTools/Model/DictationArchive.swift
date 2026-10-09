import Foundation
import Observation

/// [settings.archive]: a plain-text copy of every run, one Markdown file per day, in a folder you choose.
struct ArchiveSettings: Equatable {
    static let defaultFolder = "~/Documents/Voice Pipes"

    var enabled = false
    /// As written in config.toml (`~` allowed).
    var folder = ArchiveSettings.defaultFolder

    var folderURL: URL { URL(fileURLWithPath: (folder as NSString).expandingTildeInPath, isDirectory: true) }
}

/// Writes every run to `<folder>/YYYY/MM/YYYY-MM-DD.md` as it lands in History: the time, the track, the microphone, the app
/// in front, how long you spoke and what the run used, then the text. History (history.sqlite) is the source: the
/// archive keeps a cursor (the `seq` of the last run written) and each write appends every run after it. So nothing is
/// lost when the folder can't be written for a while (a drive unplugged, a permission refused): the next write,
/// after the next run or the minute's retry, catches up. Appends go through `fsync` before the cursor moves on.
/// `rebuild` writes the whole of History in the same form (`vp history archive`).
@MainActor
@Observable
final class DictationArchive {
    enum Status: Equatable {
        case off
        case waiting
        case wrote(file: String, at: Date)
        case failed(String)
    }

    private(set) var status = Status.off
    @ObservationIgnored private var settings = ArchiveSettings()
    @ObservationIgnored private let database: HistoryDatabase?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private let queue = DispatchQueue(label: "io.github.brancusi.voice-tools.archive")
    @ObservationIgnored private var writing = false
    @ObservationIgnored private var again = false

    /// History's `seq` of the newest run already in the archive; nil while it's off (turning it on starts from then,
    /// not from the start of History).
    nonisolated static let cursorKey = "archive.throughSeq"
    nonisolated static let retrySeconds: TimeInterval = 60

    init(database: HistoryDatabase?) {
        self.database = database
    }

    /// Applies [settings.archive]: called at launch and whenever the setting changes.
    func apply(_ new: ArchiveSettings) {
        let defaults = UserDefaults.standard
        settings = new
        timer?.invalidate()
        timer = nil
        guard new.enabled else {
            defaults.removeObject(forKey: Self.cursorKey)
            status = .off
            return
        }
        if defaults.object(forKey: Self.cursorKey) == nil, let database { defaults.set(database.lastSeq(), forKey: Self.cursorKey) }
        if status == .off { status = .waiting }
        timer = Timer.scheduledTimer(withTimeInterval: Self.retrySeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.write() }
        }
        write()
    }

    /// Appends any runs newer than the cursor. Cheap when there are none (one indexed query).
    func write() {
        guard settings.enabled, let database else { return }
        // One write at a time; a request during one runs once it's done.
        guard !writing else { again = true; return }
        writing = true
        let folder = settings.folderURL
        queue.async { [weak self] in
            let result = Self.catchUp(database: database, folder: folder)
            Task { @MainActor in
                guard let self else { return }
                self.writing = false
                if self.settings.enabled {
                    switch result {
                    case .success(let file?): self.status = .wrote(file: file, at: Date())
                    case .success(nil): break
                    case .failure(let error): self.status = .failed(error.localizedDescription)
                    }
                }
                if self.again { self.again = false; self.write() }
            }
        }
    }

    /// Rewrites the archive from the whole of History (each day's file whole), then carries on from there.
    func rebuild() async throws -> RebuildResult {
        guard settings.enabled else { throw ArchiveError.off }
        guard let database else { throw ArchiveError.noHistory }
        let folder = settings.folderURL
        let result: Result<RebuildResult, Error> = await withCheckedContinuation { done in
            queue.async {
                done.resume(with: .success(Result {
                    let result = try Self.rebuild(database: database, folder: folder)
                    if UserDefaults.standard.object(forKey: Self.cursorKey) != nil {
                        UserDefaults.standard.set(result.through, forKey: Self.cursorKey)
                    }
                    return result
                }))
            }
        }
        switch result {
        case .success(let r):
            if let last = r.lastFile { status = .wrote(file: last, at: Date()) }
            return r
        case .failure(let error):
            status = .failed(error.localizedDescription)
            throw error
        }
    }

    enum ArchiveError: LocalizedError {
        case off, noHistory
        var errorDescription: String? {
            switch self {
            case .off: "The archive is off."
            case .noHistory: "History isn't available."
            }
        }
    }

    struct RebuildResult {
        var runs: Int
        var days: Int
        /// History's `seq` of the newest run written.
        var through: Int64
        var lastFile: String?
    }

    // MARK: Writing (off the main thread)

    /// Every run in History, written to `folder` a day's file at a time, each file whole (so running it again gives
    /// the same files). Days without runs in History are left alone.
    nonisolated static func rebuild(database: HistoryDatabase, folder: URL) throws -> RebuildResult {
        let through = database.lastSeq()
        let runs = database.runs(after: 0).filter { $0.seq <= through }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        moveFlatFiles(in: folder)
        var days = 0
        var last: String?
        var start = 0
        while start < runs.count {
            let date = runs[start].record.date
            var end = start + 1
            while end < runs.count, Calendar.current.isDate(runs[end].record.date, inSameDayAs: date) { end += 1 }
            let file = folder.appendingPathComponent(path(for: date))
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let text = header(for: date) + runs[start..<end].map { entry($0.record) }.joined()
            try Data(text.utf8).write(to: file, options: .atomic)
            // A 1.17.0 file for the same day still at the top: its runs are all in the file just written.
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(file.lastPathComponent))
            days += 1
            last = path(for: date)
            start = end
        }
        return RebuildResult(runs: runs.count, days: days, through: through, lastFile: last)
    }

    /// 1.17.0 wrote `<folder>/YYYY-MM-DD.md`; files now go in `YYYY/MM/`. Moves any found there, unless that day
    /// already has a file in its new place.
    nonisolated private static func moveFlatFiles(in folder: URL) {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: folder.path) else { return }
        for name in names where name.range(of: #"^\d{4}-\d{2}-\d{2}\.md$"#, options: .regularExpression) != nil {
            let target = folder.appendingPathComponent("\(name.prefix(4))/\(name.dropFirst(5).prefix(2))/\(name)")
            guard !fm.fileExists(atPath: target.path) else { continue }
            try? fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.moveItem(at: folder.appendingPathComponent(name), to: target)
        }
    }

    /// Writes the runs after the cursor, a day's file at a time, oldest first, moving the cursor after each file.
    /// Returns the last file written, if any.
    nonisolated private static func catchUp(database: HistoryDatabase, folder: URL) -> Result<String?, Error> {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: cursorKey) != nil else { return .success(nil) }
        var cursor = Int64(defaults.integer(forKey: cursorKey))
        // History was cleared (its numbers start again at 1): every run in it is new.
        if cursor > database.lastSeq() { cursor = 0 }
        let runs = database.runs(after: cursor)
        guard !runs.isEmpty else { return .success(nil) }
        var last: String?
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            moveFlatFiles(in: folder)
            var day: [(seq: Int64, record: RunRecord)] = []
            func flush() throws {
                guard let first = day.first?.record else { return }
                let file = folder.appendingPathComponent(path(for: first.date))
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try append(day.map { entry($0.record) }.joined(), to: file, header: header(for: first.date))
                // Still on: turning it off mid-write clears the cursor, and must stay cleared.
                if defaults.object(forKey: cursorKey) != nil { defaults.set(day.last!.seq, forKey: cursorKey) }
                last = path(for: first.date)
                day = []
            }
            for run in runs {
                if let first = day.first, !Calendar.current.isDate(first.record.date, inSameDayAs: run.record.date) { try flush() }
                day.append(run)
            }
            try flush()
            return .success(last)
        } catch {
            NSLog("VoiceTools: couldn't write the archive: \(error)")
            return .failure(error)
        }
    }

    nonisolated private static func append(_ text: String, to file: URL, header: String) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: file.path) {
            guard fm.createFile(atPath: file.path, contents: Data(header.utf8)) else {
                throw CocoaError(.fileWriteNoPermission, userInfo: [NSFilePathErrorKey: file.path])
            }
        }
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
        try handle.synchronize()
    }

    /// `2026/10/2026-10-09.md`, relative to the folder.
    nonisolated static func path(for date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy/MM/yyyy-MM-dd"
        return f.string(from: date) + ".md"
    }

    nonisolated static func header(for date: Date) -> String {
        "# Voice Pipes · \(date.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))\n"
    }

    /// One run:
    ///
    ///     ## 14:32:05 · Clean dictation
    ///
    ///     - microphone: MacBook Pro Microphone
    ///     - app: Slack
    ///     - spoke: 4.3 s
    ///     - took: 1.2 s
    ///     - models: local:parakeet, google/gemini-2.5-flash
    ///
    ///     The text.
    ///
    ///     > heard: what transcription wrote, when later steps changed it
    nonisolated static func entry(_ run: RunRecord) -> String {
        let time = DateFormatter()
        time.locale = Locale(identifier: "en_US_POSIX")
        time.dateFormat = "HH:mm:ss"
        var meta: [String] = []
        if let mic = run.microphone { meta.append("microphone: \(mic)") }
        if let app = run.app { meta.append("app: \(app)") }
        if let spoke = run.spokenMs { meta.append("spoke: " + seconds(spoke)) }
        meta.append("took: " + seconds(run.totalMs))
        var models: [String] = []
        for model in (run.log ?? []).compactMap(\.model) where !models.contains(model) { models.append(model) }
        if !models.isEmpty { meta.append("models: " + models.joined(separator: ", ")) }
        if let failure = run.failure { meta.append("failed: " + oneLine(failure)) }

        var out = "\n## \(time.string(from: run.date)) · \(run.trackName)\n\n"
        out += meta.map { "- \($0)\n" }.joined()
        out += "\n\(run.text.trimmingCharacters(in: .whitespacesAndNewlines))\n"
        if let heard = run.heard?.trimmingCharacters(in: .whitespacesAndNewlines), !heard.isEmpty {
            out += "\n" + heard.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
                .map { "> " + ($0.offset == 0 ? "heard: " : "") + $0.element }.joined(separator: "\n") + "\n"
        }
        return out
    }

    nonisolated private static func seconds(_ ms: Int) -> String { String(format: "%.1f s", Double(ms) / 1000) }
    nonisolated private static func oneLine(_ s: String) -> String { s.split(whereSeparator: \.isNewline).joined(separator: " ") }
}
