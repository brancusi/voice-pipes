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
}

/// The shared word list, saved next to the tracks so it can also be edited by hand.
@MainActor
@Observable
final class VocabularyStore {
    static let shared = VocabularyStore()

    var entries: [VocabularyEntry] {
        didSet { save() }
    }

    private let fileURL = TrackStore.defaultURL.deletingLastPathComponent().appendingPathComponent("vocabulary.json")

    private init() {
        if let data = try? Data(contentsOf: fileURL), let decoded = try? JSONDecoder().decode([VocabularyEntry].self, from: data) {
            entries = decoded
        } else {
            entries = [
                VocabularyEntry(write: "Claude Code", heardAs: ["cloud code", "clawed code"]),
                VocabularyEntry(write: "OpenRouter", heardAs: ["open router"]),
                VocabularyEntry(write: "FluidAudio", heardAs: ["fluid audio"]),
            ]
            save()
        }
    }

    /// The spellings, for handing to an LLM as a glossary.
    var glossary: [String] { entries.map(\.write).filter { !$0.isEmpty } }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(entries).write(to: fileURL, options: .atomic)
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
