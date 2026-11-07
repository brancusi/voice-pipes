import Foundation

/// The text of an audio file and when each part of it is heard, for `vp play`'s read-along card. Reads ElevenLabs'
/// alignment (`/with-timestamps`: one start time per character) or a plain list of words with start times.
struct PlaybackTranscript {
    struct Mark: Equatable {
        /// UTF-16 offset into `text`.
        let offset: Int
        /// Seconds into the audio.
        let time: Double
    }

    let text: String
    /// By time (and offset). Empty: the voice's place is estimated from how far through the audio it is.
    let marks: [Mark]

    struct FormatError: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    static func load(_ url: URL) throws -> PlaybackTranscript {
        let data = try Data(contentsOf: url)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FormatError("\(url.lastPathComponent) isn't a JSON object.")
        }
        return try parse(json)
    }

    static func parse(_ json: [String: Any]) throws -> PlaybackTranscript {
        // ElevenLabs answers with `alignment` (and `normalized_alignment`) beside the audio; the bare object works too.
        let alignment = json["alignment"] as? [String: Any] ?? json
        if let characters = alignment["characters"] as? [String] {
            guard let starts = numbers(alignment["character_start_times_seconds"]), starts.count == characters.count else {
                throw FormatError("`character_start_times_seconds` needs one time per character.")
            }
            return fromCharacters(characters, starts: starts)
        }
        if let words = json["words"] as? [[String: Any]] {
            return try fromWords(words, text: json["text"] as? String)
        }
        throw FormatError("Expected ElevenLabs alignment ({\"alignment\": {\"characters\": …}}) or {\"text\", \"words\": [{\"word\", \"start\"}]}.")
    }

    /// A mark at each character (they're all timed), so the card's word cursor follows the voice letter by letter.
    static func fromCharacters(_ characters: [String], starts: [Double]) -> PlaybackTranscript {
        var text = ""
        var offset = 0
        var marks: [Mark] = []
        marks.reserveCapacity(characters.count)
        for (character, start) in zip(characters, starts) {
            marks.append(Mark(offset: offset, time: start))
            text += character
            offset += character.utf16.count
        }
        return PlaybackTranscript(text: text, marks: sorted(marks))
    }

    /// Each word is found in the text in order (the text as written, with its punctuation); without a text, the words
    /// are joined with spaces. A word that isn't found is skipped.
    static func fromWords(_ words: [[String: Any]], text given: String?) throws -> PlaybackTranscript {
        let pairs: [(String, Double)] = words.compactMap { entry in
            guard let word = entry["word"] as? String ?? entry["text"] as? String,
                  let start = number(entry["start"]) else { return nil }
            return (word, start)
        }
        guard !pairs.isEmpty else { throw FormatError("`words` needs entries like {\"word\": \"Hey\", \"start\": 0.12}.") }
        let text = given ?? pairs.map(\.0).joined(separator: " ")
        let all = text as NSString
        var cursor = 0
        var marks: [Mark] = []
        for (word, start) in pairs {
            let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let found = all.range(of: trimmed, options: [], range: NSRange(location: cursor, length: all.length - cursor))
            guard found.location != NSNotFound else { continue }
            marks.append(Mark(offset: found.location, time: start))
            cursor = found.location + found.length
        }
        return PlaybackTranscript(text: text, marks: sorted(marks))
    }

    /// Where the voice is at `time`: the last mark at or before it.
    func offset(at time: Double) -> Int? {
        var low = 0, high = marks.count
        while low < high {
            let mid = (low + high) / 2
            if marks[mid].time <= time { low = mid + 1 } else { high = mid }
        }
        return low > 0 ? marks[low - 1].offset : nil
    }

    /// When the voice reaches `offset`: the first mark at or after it.
    func time(at offset: Int) -> Double? {
        marks.first { $0.offset >= offset }?.time
    }

    private static func sorted(_ marks: [Mark]) -> [Mark] {
        marks.sorted { ($0.time, $0.offset) < ($1.time, $1.offset) }
    }

    private static func number(_ value: Any?) -> Double? {
        (value as? Double) ?? (value as? Int).map(Double.init) ?? (value as? NSNumber)?.doubleValue
    }

    private static func numbers(_ value: Any?) -> [Double]? {
        (value as? [Any])?.compactMap(number)
    }
}
