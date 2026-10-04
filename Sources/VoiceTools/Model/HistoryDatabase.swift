import Foundation
import SQLite3

/// Every run ever, in `history.sqlite` (Application Support, beside the tracks' cache). One row per run: the whole
/// `RunRecord` as JSON, plus the columns History filters on. Kept forever; nothing loads it all. The app holds only
/// the newest runs in memory and asks for pages; `vp history` reads the same file directly, app running or not.
///
/// WAL mode, so the CLI reads while the app writes. Search is substring, case-insensitive, over the text, what was
/// heard and the track name, through an FTS5 trigram index (a scan for one or two characters). Each step that names
/// a model also gets a row in `step_models`, so the model pickers' measured speeds and costs are one indexed query.
/// Before 1.9.0 history was `history.json` (the last 1,000 runs); it's imported once and left in place as a backup.
final class HistoryDatabase: @unchecked Sendable {
    nonisolated static let defaultURL = TrackStore.defaultURL.deletingLastPathComponent().appendingPathComponent("history.sqlite")
    nonisolated static let legacyURL = TrackStore.defaultURL.deletingLastPathComponent().appendingPathComponent("history.json")

    /// What to list: a track, words to find, and where the last page ended.
    struct Query: Equatable {
        var track: String?
        var search = ""
        /// The `seq` of the last run already shown; the page starts after it (older).
        var before: Int64?
        /// Only runs from this moment on.
        var since: Date?
    }

    private var db: OpaquePointer?
    private let lock = NSLock()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    enum Failure: Error, CustomStringConvertible {
        case sqlite(String)
        var description: String { if case .sqlite(let m) = self { m } else { "" } }
    }

    init(url: URL = HistoryDatabase.defaultURL, legacyJSON: URL? = HistoryDatabase.legacyURL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "can't open"
            sqlite3_close(db)
            db = nil
            throw Failure.sqlite("history.sqlite: \(message)")
        }
        sqlite3_busy_timeout(db, 5000)
        try exec("""
            PRAGMA journal_mode = WAL;
            PRAGMA synchronous = NORMAL;
            PRAGMA foreign_keys = ON;
            CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT);
            CREATE TABLE IF NOT EXISTS runs (
                seq INTEGER PRIMARY KEY,
                id TEXT NOT NULL UNIQUE,
                date REAL NOT NULL,
                track TEXT NOT NULL,
                text TEXT NOT NULL,
                heard TEXT,
                failed INTEGER NOT NULL DEFAULT 0,
                record TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS runs_by_date ON runs (date);
            CREATE INDEX IF NOT EXISTS runs_by_track ON runs (track, date);
            CREATE TABLE IF NOT EXISTS step_models (
                run INTEGER NOT NULL REFERENCES runs (seq) ON DELETE CASCADE,
                model TEXT NOT NULL,
                entry TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS step_models_by_model ON step_models (model, run);
            CREATE INDEX IF NOT EXISTS step_models_by_run ON step_models (run);
            CREATE VIRTUAL TABLE IF NOT EXISTS runs_search USING fts5 (
                track, text, heard, content = 'runs', content_rowid = 'seq', tokenize = 'trigram'
            );
            CREATE TRIGGER IF NOT EXISTS runs_search_insert AFTER INSERT ON runs BEGIN
                INSERT INTO runs_search (rowid, track, text, heard) VALUES (new.seq, new.track, new.text, new.heard);
            END;
            CREATE TRIGGER IF NOT EXISTS runs_search_delete AFTER DELETE ON runs BEGIN
                INSERT INTO runs_search (runs_search, rowid, track, text, heard) VALUES ('delete', old.seq, old.track, old.text, old.heard);
            END;
            """)
        if let legacyJSON { try importLegacy(legacyJSON) }
    }

    deinit { sqlite3_close(db) }

    // MARK: Writing

    func insert(_ record: RunRecord) throws {
        try locked {
            try exec("BEGIN IMMEDIATE")
            do {
                try insertRow(record)
                try exec("COMMIT")
            } catch {
                try? exec("ROLLBACK")
                throw error
            }
        }
    }

    func clear() throws {
        try locked { try exec("DELETE FROM step_models; DELETE FROM runs; INSERT INTO runs_search (runs_search) VALUES ('rebuild');") }
    }

    private func insertRow(_ record: RunRecord) throws {
        let json = String(decoding: try encoder.encode(record), as: UTF8.self)
        try run("INSERT OR IGNORE INTO runs (id, date, track, text, heard, failed, record) VALUES (?, ?, ?, ?, ?, ?, ?)",
                [.text(record.id.uuidString), .real(record.date.timeIntervalSince1970), .text(record.trackName), .text(record.text),
                 record.heard.map(Value.text) ?? .null, .int(record.failure == nil ? 0 : 1), .text(json)])
        guard sqlite3_changes(db) > 0 else { return }  // already there (an import that ran twice)
        let seq = sqlite3_last_insert_rowid(db)
        for entry in record.log ?? [] where entry.status == .ok {
            guard let model = entry.model else { continue }
            let entryJSON = String(decoding: try encoder.encode(entry), as: UTF8.self)
            try run("INSERT INTO step_models (run, model, entry) VALUES (?, ?, ?)", [.int(seq), .text(model), .text(entryJSON)])
        }
    }

    /// history.json → here, once (by whichever of the app and `vp` gets there first).
    private func importLegacy(_ url: URL) throws {
        try locked {
            try exec("BEGIN IMMEDIATE")
            do {
                if try scalarText("SELECT value FROM meta WHERE key = 'imported_json'") == nil {
                    var note = "no history.json"
                    if let data = try? Data(contentsOf: url) {
                        if let records = try? decoder.decode([RunRecord].self, from: data) {
                            // Oldest first, so `seq` follows time like new runs do.
                            for record in records.sorted(by: { $0.date < $1.date }) { try insertRow(record) }
                            note = "\(records.count) runs"
                        } else {
                            note = "history.json wasn't readable; left as it is"
                            NSLog("VoiceTools: \(note)")
                        }
                    }
                    try run("INSERT INTO meta (key, value) VALUES ('imported_json', ?)", [.text("\(note), \(ISO8601DateFormatter().string(from: Date()))")])
                }
                try exec("COMMIT")
            } catch {
                try? exec("ROLLBACK")
                throw error
            }
        }
    }

    // MARK: Reading

    /// Newest first, `limit` at a time; pass the last page's final `seq` as `before` for the next.
    func runs(_ query: Query = Query(), limit: Int) -> [(seq: Int64, record: RunRecord)] {
        let (sql, values) = whereClause(query)
        return (try? locked {
            try select("SELECT seq, record FROM runs\(sql) ORDER BY seq DESC LIMIT \(max(0, limit))", values) { row in
                (row.int(0), row.text(1))
            }
        })?.compactMap { seq, json in
            (try? decoder.decode(RunRecord.self, from: Data(json.utf8))).map { (seq, $0) }
        } ?? []
    }

    /// Matching runs with their number in the whole History (1 = newest), newest first; no limit = all of them.
    func numberedRuns(_ query: Query = Query(), limit: Int?) -> [(n: Int, record: RunRecord)] {
        let (sql, values) = whereClause(query)
        let numbered = "SELECT n, record FROM (SELECT *, row_number() OVER (ORDER BY seq DESC) AS n FROM runs) AS runs"
        let rows = (try? locked {
            try select(numbered + sql + " ORDER BY seq DESC" + (limit.map { " LIMIT \(max(0, $0))" } ?? ""), values) {
                (Int($0.int(0)), $0.text(1))
            }
        }) ?? []
        return rows.compactMap { n, json in (try? decoder.decode(RunRecord.self, from: Data(json.utf8))).map { (n, $0) } }
    }

    /// How many runs match (ignoring `before`).
    func count(_ query: Query = Query()) -> Int {
        var query = query
        query.before = nil
        let (sql, values) = whereClause(query)
        let n = try? locked { try select("SELECT count(*) FROM runs\(sql)", values) { Int($0.int(0)) }.first }
        return (n ?? nil) ?? 0
    }

    /// The `n`th newest run matching (1 = newest).
    func run(number n: Int, _ query: Query = Query()) -> RunRecord? {
        guard n >= 1 else { return nil }
        let (sql, values) = whereClause(query)
        let json = try? locked { try select("SELECT record FROM runs\(sql) ORDER BY seq DESC LIMIT 1 OFFSET \(n - 1)", values) { $0.text(0) }.first }
        return (json ?? nil).flatMap { try? decoder.decode(RunRecord.self, from: Data($0.utf8)) }
    }

    /// How many runs are newer than this one (0 = it's the newest), or nil if it isn't there.
    func position(of id: RunRecord.ID) -> Int? {
        let n = try? locked {
            try select("SELECT (SELECT count(*) FROM runs AS newer WHERE newer.seq > runs.seq) FROM runs WHERE id = ?", [.text(id.uuidString)]) { Int($0.int(0)) }.first
        }
        return n ?? nil
    }

    /// Runs since a moment, newest first (usage totals).
    func runs(since date: Date) -> [RunRecord] {
        let rows = (try? locked {
            try select("SELECT record FROM runs WHERE date >= ? ORDER BY seq DESC", [.real(date.timeIntervalSince1970)]) { $0.text(0) }
        }) ?? []
        return rows.compactMap { try? decoder.decode(RunRecord.self, from: Data($0.utf8)) }
    }

    /// Every track name in History, most recently used first.
    func trackNames() -> [String] {
        (try? locked { try select("SELECT track FROM runs GROUP BY track ORDER BY max(seq) DESC", []) { $0.text(0) } }) ?? []
    }

    /// A model's successful steps, newest first.
    func entries(model: String, limit: Int) -> [RunRecord.LogEntry] {
        let rows = (try? locked {
            try select("SELECT entry FROM step_models WHERE model = ? ORDER BY run DESC LIMIT \(limit)", [.text(model)]) { $0.text(0) }
        }) ?? []
        return rows.compactMap { try? decoder.decode(RunRecord.LogEntry.self, from: Data($0.utf8)) }
    }

    private func whereClause(_ query: Query) -> (String, [Value]) {
        var conditions: [String] = []
        var values: [Value] = []
        if let track = query.track {
            conditions.append("track = ?")
            values.append(.text(track))
        }
        let search = query.search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !search.isEmpty {
            let pattern = "%" + search.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%")
                .replacingOccurrences(of: "_", with: "\\_") + "%"
            // The trigram index answers LIKE for three characters or more; shorter searches scan.
            let like = "(text LIKE ? ESCAPE '\\' OR heard LIKE ? ESCAPE '\\' OR track LIKE ? ESCAPE '\\')"
            if search.count >= 3 {
                conditions.append("seq IN (SELECT rowid FROM runs_search WHERE runs_search MATCH ?)")
                values.append(.text(Self.trigramPhrase(search)))
            }
            conditions.append(like)
            values += [.text(pattern), .text(pattern), .text(pattern)]
        }
        if let since = query.since {
            conditions.append("date >= ?")
            values.append(.real(since.timeIntervalSince1970))
        }
        if let before = query.before {
            conditions.append("seq < ?")
            values.append(.int(before))
        }
        return (conditions.isEmpty ? "" : " WHERE " + conditions.joined(separator: " AND "), values)
    }

    /// The search as one FTS5 phrase: every run containing the substring has all its trigrams, in order. The LIKE
    /// beside it keeps the exact match.
    private static func trigramPhrase(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: SQLite

    enum Value {
        case null, int(Int64), real(Double), text(String)
    }

    struct Row {
        let statement: OpaquePointer?
        func int(_ column: Int32) -> Int64 { sqlite3_column_int64(statement, column) }
        func text(_ column: Int32) -> String { sqlite3_column_text(statement, column).map { String(cString: $0) } ?? "" }
    }

    private func locked<T>(_ body: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        guard db != nil else { throw Failure.sqlite("history.sqlite isn't open") }
        return try body()
    }

    private func exec(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? "failed"
            sqlite3_free(error)
            throw Failure.sqlite(message)
        }
    }

    private func prepare(_ sql: String, _ values: [Value]) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw Failure.sqlite(String(cString: sqlite3_errmsg(db)))
        }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, value) in values.enumerated() {
            let i = Int32(index + 1)
            switch value {
            case .null: sqlite3_bind_null(statement, i)
            case .int(let v): sqlite3_bind_int64(statement, i, v)
            case .real(let v): sqlite3_bind_double(statement, i, v)
            case .text(let v): sqlite3_bind_text(statement, i, v, -1, transient)
            }
        }
        return statement
    }

    private func run(_ sql: String, _ values: [Value]) throws {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw Failure.sqlite(String(cString: sqlite3_errmsg(db))) }
    }

    private func select<T>(_ sql: String, _ values: [Value], _ map: (Row) -> T) throws -> [T] {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        var out: [T] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW: out.append(map(Row(statement: statement)))
            case SQLITE_DONE: return out
            default: throw Failure.sqlite(String(cString: sqlite3_errmsg(db)))
            }
        }
    }

    private func scalarText(_ sql: String) throws -> String? {
        try select(sql, []) { $0.text(0) }.first
    }
}
