import Foundation
import Observation

/// One word or phrase in the shared vocabulary: how to write it, and what transcription tends to produce instead.
struct VocabularyEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    /// The spelling to use, e.g. "Claude Code".
    var write: String
    /// Mishearings to replace, e.g. ["cloud code", "clawed code"]. Matched as whole words, ignoring case.
    var heardAs: [String]
    /// Write it exactly as typed even at the start of a sentence (for lowercase terms like "kubectl").
    var alwaysExact = false
    /// The Heard-as field exactly as typed, so editing doesn't reformat it mid-keystroke. Not saved.
    var heardAsText: String?

    enum CodingKeys: String, CodingKey { case id, write, heardAs, alwaysExact }
}

/// The shared word list, in ~/.config/voice-pipes/vocabulary.toml beside config.toml. Edits from outside the app
/// apply within a second; a file that doesn't check out keeps the last good list and reports `issues`.
@MainActor
@Observable
final class VocabularyStore {
    static let shared = VocabularyStore()

    var entries: [VocabularyEntry] {
        didSet { if !applyingFile { save() } }
    }

    private(set) var issues: [ConfigIssue] = []
    @ObservationIgnored var onIssuesChanged: () -> Void = {}

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private let legacyURL = TrackStore.defaultURL.deletingLastPathComponent().appendingPathComponent("vocabulary.json")
    @ObservationIgnored private var applyingFile = false
    @ObservationIgnored private var diskText: String?
    @ObservationIgnored private var watcher: FileWatcher?

    nonisolated static let starters = [
        VocabularyEntry(write: "Claude Code", heardAs: ["cloud code", "clawed code"]),
        VocabularyEntry(write: "OpenRouter", heardAs: ["open router"]),
        VocabularyEntry(write: "FluidAudio", heardAs: ["fluid audio"]),
    ]

    init(fileURL: URL = ConfigPaths.vocabulary, watch: Bool = true) {
        self.fileURL = fileURL
        let cached = (try? Data(contentsOf: legacyURL)).flatMap { try? JSONDecoder().decode([VocabularyEntry].self, from: $0) }
        if let text = try? String(contentsOf: fileURL, encoding: .utf8) {
            diskText = text
            let result = VocabularyFile.parse(text)
            entries = result.entries ?? cached ?? Self.starters
            issues = result.errors + result.warnings
        } else {
            // 1.6.0: the list moves from vocabulary.json to vocabulary.toml, once (the JSON stays as a last-good copy).
            entries = cached ?? Self.starters
            save()
        }
        if watch { watcher = FileWatcher(fileURL) { [weak self] in self?.reloadFromDisk() } }
    }

    /// The spellings, for handing to an LLM as a glossary.
    var glossary: [String] { entries.map(\.write).filter { !$0.isEmpty } }

    func reloadFromDisk() {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8), text != diskText else { return }
        if let previous = diskText { ConfigBackups.save(previous, of: fileURL, in: backupsURL) }
        diskText = text
        let result = VocabularyFile.parse(text)
        if let parsed = result.entries {
            applyingFile = true
            entries = parsed
            applyingFile = false
            writeCache()
        }
        setIssues(result.errors + result.warnings)
    }

    private var backupsURL: URL { fileURL.deletingLastPathComponent().appendingPathComponent("backups", isDirectory: true) }

    private func setIssues(_ new: [ConfigIssue]) {
        guard new != issues else { return }
        issues = new
        onIssuesChanged()
    }

    private func save() {
        let text = VocabularyFile.write(entries)
        guard text != diskText else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let previous = diskText { ConfigBackups.save(previous, of: fileURL, minimumGap: 60, in: backupsURL) }
        do {
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
            diskText = text
            watcher?.noteWrite(fileURL)
            writeCache()
            setIssues([])
        } catch {
            NSLog("VoiceTools: failed to save vocabulary.toml: \(error)")
        }
    }

    private func writeCache() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(entries).write(to: legacyURL, options: .atomic)
    }
}

/// Mechanical find-and-replace for the vocabulary. No model, no network: the same input always gives the same output.
enum FixWords {
    /// Replaces every listed mishearing (and any other casing of the spelling itself) with the spelling.
    /// Whole words only, longest phrase first, punctuation around a match left as is.
    static func apply(_ text: String, entries: [VocabularyEntry]) -> String {
        var byPhrase: [String: VocabularyEntry] = [:]
        for entry in entries where !entry.write.trimmingCharacters(in: .whitespaces).isEmpty {
            for phrase in entry.heardAs + [entry.write] {
                let key = normalize(phrase)
                if !key.isEmpty, byPhrase[key] == nil { byPhrase[key] = entry }
            }
        }
        guard !byPhrase.isEmpty else { return text }

        // Longest first, so "cloud code review" wins over "cloud code" when both are listed.
        let alternatives = byPhrase.keys.sorted { $0.count > $1.count }.map { phrase in
            phrase.split(separator: " ").map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: "\\s+")
        }
        let pattern = "(?<![\\p{L}\\p{N}])(?:\(alternatives.joined(separator: "|")))(?![\\p{L}\\p{N}])"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }

        let ns = text as NSString
        var result = ""
        var cursor = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let matched = ns.substring(with: match.range)
            guard let entry = byPhrase[normalize(matched)] else { continue }
            result += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let before = ns.substring(to: match.range.location)
            result += spelling(entry, atSentenceStart: isSentenceStart(before))
            cursor = match.range.location + match.range.length
        }
        result += ns.substring(from: cursor)
        return result
    }

    /// Entries with capitals are written exactly; all-lowercase ones get a capital first letter at a sentence start,
    /// unless marked "always exact".
    static func spelling(_ entry: VocabularyEntry, atSentenceStart: Bool) -> String {
        let word = entry.write.trimmingCharacters(in: .whitespaces)
        guard atSentenceStart, !entry.alwaysExact, word == word.lowercased(), let first = word.first else { return word }
        return first.uppercased() + word.dropFirst()
    }

    /// True at the start of the text, or after ".", "?" or "!" (skipping spaces and opening quotes or brackets).
    static func isSentenceStart(_ before: String) -> Bool {
        let trimmed = before.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"“‘'([")))
        guard let last = trimmed.last else { return true }
        return ".?!".contains(last)
    }

    private static func normalize(_ phrase: String) -> String {
        phrase.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
