import Foundation

/// A voiceover script (`vp record-vo`): the text shown in the HUD, its words for following the reader, and the cue
/// markers (`[3]`) taken out of the text, each remembered at the word after it.
struct VoiceoverScript {
    /// One word as compared with what was heard: lowercased, without punctuation. A hyphenated word is several.
    struct Token {
        let norm: String
        /// The written word it's part of.
        let word: Int
    }

    struct Word {
        let text: String
        /// UTF-16 range in `text`.
        let range: NSRange
        let sentence: Int
    }

    struct Marker {
        let id: String
        /// The word it comes before (`words.count` when it's at the very end).
        let word: Int
    }

    let text: String
    let words: [Word]
    let tokens: [Token]
    let markers: [Marker]
    /// The card's sentences (as the read-along card splits them), and where each starts in `tokens`.
    let sentences: [Speaker.Sentence]
    let sentenceTokens: [Range<Int>]

    /// Markdown emphasis is dropped, `[id]` markers are taken out, lines within a paragraph are joined, and blank
    /// lines stay paragraph breaks.
    init(_ source: String) {
        let paragraphs = source.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
            .map { $0.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ") }
            .map { $0.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "__", with: "") }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        var text = ""
        var words: [(String, NSRange)] = []
        var markers: [(String, Int)] = []
        let idCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_.:-"))
        for (index, paragraph) in paragraphs.enumerated() {
            if index > 0 { text += "\n\n" }
            var first = true
            for piece in paragraph.split(whereSeparator: \.isWhitespace) {
                // A marker can stick to the word after it: "[3]Here's".
                var rest = Substring(piece)
                while rest.first == "[", let close = rest.firstIndex(of: "]") {
                    let id = rest[rest.index(after: rest.startIndex)..<close]
                    guard !id.isEmpty, id.unicodeScalars.allSatisfy(idCharacters.contains) else { break }
                    markers.append((String(id), words.count))
                    rest = rest[rest.index(after: close)...]
                }
                guard !rest.isEmpty else { continue }
                if !first { text += " " }
                first = false
                let start = (text as NSString).length
                text += rest
                words.append((String(rest), NSRange(location: start, length: (text as NSString).length - start)))
            }
        }
        self.text = text
        let sentences = Speaker.sentences(of: text)
        self.sentences = sentences
        func sentence(at offset: Int) -> Int { sentences.lastIndex { $0.start <= offset } ?? 0 }
        self.words = words.map { Word(text: $0.0, range: $0.1, sentence: sentence(at: $0.1.location)) }
        self.markers = markers.map { Marker(id: $0.0, word: $0.1) }
        var tokens: [Token] = []
        var ranges = Array(repeating: 0..<0, count: sentences.count)
        for (index, word) in self.words.enumerated() {
            let before = tokens.count
            tokens += Self.normalize(word.text).map { Token(norm: $0, word: index) }
            let r = ranges[word.sentence]
            ranges[word.sentence] = (r.isEmpty ? before : r.lowerBound)..<tokens.count
        }
        self.tokens = tokens
        // A sentence with no words (only punctuation) still has a place.
        var next = 0
        sentenceTokens = ranges.map { r in
            defer { next = max(next, r.upperBound) }
            return r.isEmpty ? next..<next : r
        }
    }

    /// Lowercased, apostrophes and punctuation dropped, split at hyphens, dashes and slashes ("month-by-month" is three
    /// words, as transcription writes it). Numbers are spelled out ("3" and "three" are the same word, "3rd" is "third",
    /// "2.5" is "two point five"), whichever way the script or the transcription wrote them.
    static func normalize(_ word: String) -> [String] {
        word.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .components(separatedBy: CharacterSet(charactersIn: "-–—/"))
            .flatMap { part -> [String] in
                if let spelled = spellNumber(part) { return spelled }
                let plain = part.filter { $0.isLetter || $0.isNumber }
                return plain.isEmpty ? [] : [plain]
            }
    }

    nonisolated(unsafe) private static let cardinal: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US")
        f.numberStyle = .spellOut
        return f
    }()

    /// "3", "$40", "45%", "1,000", "2.5", "3rd" as words; nil when it isn't a number.
    private static func spellNumber(_ part: String) -> [String]? {
        let core = part.trimmingCharacters(in: CharacterSet.alphanumerics.inverted).replacingOccurrences(of: ",", with: "")
        guard let digit = core.first, digit.isNumber, digit.isASCII else { return nil }
        let digits = core.prefix { $0.isASCII && ($0.isNumber || $0 == ".") }
        let suffix = core.dropFirst(digits.count)
        let spelled: String?
        if ["st", "nd", "rd", "th"].contains(suffix), let n = Int(digits) {
            spelled = ordinalWord(n)
        } else if suffix.isEmpty, digits.filter({ $0 == "." }).count <= 1, let n = Double(digits), n < 1e12 {
            spelled = cardinal.string(from: NSNumber(value: n))
        } else {
            spelled = nil
        }
        return spelled?.split(whereSeparator: { $0 == " " || $0 == "-" }).map { $0.filter(\.isLetter) }.filter { !$0.isEmpty }
    }

    /// 21 → "twenty-first": the cardinal with its last word made ordinal.
    private static func ordinalWord(_ n: Int) -> String? {
        guard var words = cardinal.string(from: NSNumber(value: n))?.components(separatedBy: CharacterSet(charactersIn: " -")),
              let last = words.popLast() else { return nil }
        let irregular = ["one": "first", "two": "second", "three": "third", "five": "fifth", "eight": "eighth", "nine": "ninth",
                         "twelve": "twelfth"]
        let made = irregular[last] ?? (last.hasSuffix("y") ? String(last.dropLast()) + "ieth" : last + "th")
        return (words + [made]).joined(separator: " ")
    }

    static func normalizeHeard(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).flatMap { normalize(String($0)) }
    }

    /// Same word, allowing a letter or two of difference in a longer one (a misheard ending, British spelling).
    static func same(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let n = min(a.count, b.count)
        guard n >= 4 else { return false }
        return distance(a, b, limit: n >= 8 ? 2 : 1) != nil
    }

    /// Edit distance if it's at most `limit`.
    private static func distance(_ a: String, _ b: String, limit: Int) -> Int? {
        let a = Array(a), b = Array(b)
        guard abs(a.count - b.count) <= limit else { return nil }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            guard current.min()! <= limit else { return nil }
            previous = current
        }
        return previous[b.count] <= limit ? previous[b.count] : nil
    }

    // MARK: Following the reader

    /// Follows the reader through the script from live transcription of the last few seconds (a rolling window, so the
    /// same words come round again: following them again changes nothing). `cursor` is the last token read (-1 before
    /// the first). It moves forward to where the latest heard words match the script, skipping a word or two when the
    /// words before agree, never back on a stray word; it goes back only when the reader restarts a sentence (its first
    /// three words, again).
    struct Follower {
        let script: VoiceoverScript
        private(set) var cursor = -1

        init(script: VoiceoverScript, from token: Int = -1) {
            self.script = script
            cursor = token
        }

        /// What transcription heard in the last few seconds.
        mutating func follow(_ recent: String) {
            let heard = VoiceoverScript.normalizeHeard(recent)
            guard !heard.isEmpty, !restarted(heard) else { return }
            // The last word, or the one before it if the last was an ad-lib or cut off mid-word.
            for anchor in 0..<min(2, heard.count) {
                if advance(Array(heard.dropLast(anchor))) { return }
            }
        }

        private mutating func advance(_ heard: [String]) -> Bool {
            let tokens = script.tokens
            guard let last = heard.last, cursor + 1 < tokens.count else { return false }
            let context = Array(heard.dropLast().suffix(5))
            // Where we are now competes too, and wins a tie: the same words heard again keep the place.
            var best: (p: Int, score: Int)?
            for p in max(0, cursor)...min(cursor + 15, tokens.count - 1) where VoiceoverScript.same(tokens[p].norm, last) {
                let score = 1 + VoiceoverScript.lcs(context, tokens[max(0, p - 6)..<p].map(\.norm))
                if score > (best?.score ?? 0) { best = (p, score) }  // ties keep the nearer place
            }
            guard let best else { return false }
            if best.p <= cursor { return true }
            guard best.score >= 2 || best.p == cursor + 1 else { return false }
            cursor = best.p
            return true
        }

        /// The first three words of this sentence (or the one before), again: the reader started it over.
        private mutating func restarted(_ heard: [String]) -> Bool {
            guard heard.count >= 3, cursor >= 0 else { return false }
            let tokens = script.tokens
            let three = Array(heard.suffix(3))
            let current = script.words[tokens[min(cursor + 1, tokens.count - 1)].word].sentence
            for s in [current, current - 1] where s >= 0 {
                let r = script.sentenceTokens[s]
                guard r.count >= 3, r.lowerBound + 2 < cursor else { continue }
                if (0..<3).allSatisfy({ VoiceoverScript.same(tokens[r.lowerBound + $0].norm, three[$0]) }) {
                    cursor = r.lowerBound + 2
                    return true
                }
            }
            return false
        }

        /// Where the card's cursor goes: the start of the next word to read.
        var position: Int {
            let next = cursor + 1
            guard next < script.tokens.count else { return (script.text as NSString).length }
            return script.words[script.tokens[next].word].range.location
        }

        var finished: Bool { cursor >= script.tokens.count - 1 }
    }

    /// Longest common subsequence length, by `same`.
    static func lcs(_ a: [String], _ b: [String]) -> Int {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        var previous = Array(repeating: 0, count: b.count + 1)
        for x in a {
            var current = [0]
            for (j, y) in b.enumerated() {
                current.append(same(x, y) ? previous[j] + 1 : max(previous[j + 1], current[j]))
            }
            previous = current
        }
        return previous[b.count]
    }

    // MARK: Aligning a take

    struct HeardWord {
        let word: String
        let start: Double
        let end: Double
    }

    struct Alignment {
        struct TimedWord { let word: String; let start: Double; let end: Double; let matched: Bool }
        struct SentenceTime { let index: Int; let text: String; let start: Double?; let end: Double?; let matched: Double }
        struct MarkerTime { let id: String; let time: Double?; let word: String? }

        let words: [TimedWord]
        let sentences: [SentenceTime]
        let markers: [MarkerTime]
    }

    /// Times for the script from what a final transcription heard. Each sentence takes its last good reading (a
    /// restart replaces the flubbed one), working back from the end so the sentences stay in order. Script words that
    /// weren't heard get times between their neighbours'.
    func align(_ heardWords: [HeardWord]) -> Alignment {
        var heard: [(norm: String, word: Int)] = []
        for (index, word) in heardWords.enumerated() {
            heard += Self.normalize(word.word).map { ($0, index) }
        }
        // Script token → heard token, for tokens matched or substituted.
        var link = [Int?](repeating: nil, count: tokens.count)
        var exact = [Bool](repeating: false, count: tokens.count)
        var sentenceMatch = [Double](repeating: 0, count: sentences.count)
        var found = [Bool](repeating: false, count: sentences.count)
        var bound = heard.count
        for s in sentences.indices.reversed() {
            let r = sentenceTokens[s]
            guard !r.isEmpty, bound > 0 else { continue }
            guard let take = Self.lastTake(Array(tokens[r].map(\.norm)), in: Array(heard[..<bound].map(\.norm))) else { continue }
            found[s] = true
            for (i, h, same) in take.pairs {
                link[r.lowerBound + i] = h
                exact[r.lowerBound + i] = same
            }
            sentenceMatch[s] = Double(take.pairs.filter(\.2).count) / Double(r.count)
            bound = take.start
        }
        // A sentence not found (reworded, ad-libbed) still has its place: the words heard between the sentences either
        // side. It takes its best reading there, however loose, starting where that stretch starts, or else is spread
        // over it; its markers get times, its `matched` says how close it was.
        for s in sentences.indices where !found[s] {
            let r = sentenceTokens[s]
            guard !r.isEmpty else { continue }
            let lo = link[..<r.lowerBound].compactMap { $0 }.max().map { $0 + 1 } ?? 0
            let hi = link[r.upperBound...].compactMap { $0 }.min() ?? heard.count
            guard lo < hi else { continue }
            found[s] = true
            if let take = Self.lastTake(tokens[r].map(\.norm), in: heard[lo..<hi].map(\.norm), minimum: -.max / 2) {
                for (i, h, same) in take.pairs {
                    link[r.lowerBound + i] = lo + h
                    exact[r.lowerBound + i] = same
                }
                if link[r.lowerBound] == nil { link[r.lowerBound] = lo }
                sentenceMatch[s] = Double(take.pairs.filter(\.2).count) / Double(r.count)
            } else {
                for i in 0..<r.count { link[r.lowerBound + i] = lo + i * (hi - lo) / r.count }
            }
        }

        // Token times, then word times (a word spans its tokens).
        var tokenStart = [Double?](repeating: nil, count: tokens.count)
        var tokenEnd = [Double?](repeating: nil, count: tokens.count)
        for t in tokens.indices {
            if let h = link[t] {
                tokenStart[t] = heardWords[heard[h].word].start
                tokenEnd[t] = heardWords[heard[h].word].end
            }
        }
        // Unheard tokens: between the neighbours that were.
        for t in tokens.indices where tokenStart[t] == nil {
            let before = tokens.indices[..<t].last { tokenEnd[$0] != nil }.flatMap { tokenEnd[$0] }
            let after = tokens.indices[(t + 1)...].first { tokenStart[$0] != nil }.flatMap { tokenStart[$0] }
            if let time = before ?? after {
                tokenStart[t] = time
                tokenEnd[t] = after ?? time
            }
        }
        var timed: [Alignment.TimedWord] = []
        for (index, word) in words.enumerated() {
            let mine = tokens.indices.filter { tokens[$0].word == index }
            let start = mine.compactMap { tokenStart[$0] }.min() ?? 0
            let end = mine.compactMap { tokenEnd[$0] }.max() ?? start
            timed.append(.init(word: word.text, start: start, end: max(start, end), matched: !mine.isEmpty && mine.allSatisfy { exact[$0] }))
        }
        let sentenceTimes = sentences.indices.map { s -> Alignment.SentenceTime in
            let mine = words.indices.filter { words[$0].sentence == s }
            return .init(index: s + 1, text: sentences[s].text,
                         start: found[s] ? mine.first.map { timed[$0].start } : nil,
                         end: found[s] ? mine.last.map { timed[$0].end } : nil,
                         matched: (sentenceMatch[s] * 100).rounded() / 100)
        }
        let markerTimes = markers.map { marker -> Alignment.MarkerTime in
            if marker.word < timed.count {
                let found = found[words[marker.word].sentence]
                return .init(id: marker.id, time: found ? timed[marker.word].start : nil, word: words[marker.word].text)
            }
            return .init(id: marker.id, time: timed.last?.end, word: nil)
        }
        return Alignment(words: timed, sentences: sentenceTimes, markers: markerTimes)
    }

    /// The last reading of a sentence (`script` tokens) in `heard`: a semi-global alignment (the sentence whole, any
    /// stretch of heard), taking the latest end that scores at least half marks and near the best. Pairs are
    /// (script index, heard index, same word).
    /// `minimum` lowers the bar (any reading at all, for a sentence whose place is already known).
    static func lastTake(_ script: [String], in heard: [String], minimum: Int? = nil) -> (start: Int, pairs: [(Int, Int, Bool)])? {
        let n = script.count, m = heard.count
        guard n > 0, m > 0 else { return nil }
        // dp[i][j]: best score of script[..<i] ending at heard[..<j]. Match +2, substitution -1, a skipped word on
        // either side -1.
        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in 1...n { dp[i][0] = -i }
        for i in 1...n {
            for j in 1...m {
                let same = Self.same(script[i - 1], heard[j - 1])
                dp[i][j] = max(dp[i - 1][j - 1] + (same ? 2 : -1), dp[i - 1][j] - 1, dp[i][j - 1] - 1)
            }
        }
        let best = (1...m).map { dp[n][$0] }.max() ?? 0
        guard best >= minimum ?? max(2, n) else { return nil }  // at least half the sentence
        let threshold = minimum == nil ? max(n, Int((Double(best) * 0.8).rounded(.up))) : best
        guard let end = (1...m).last(where: { dp[n][$0] >= threshold }) else { return nil }
        // Back through the table, preferring matches.
        var i = n, j = end
        var pairs: [(Int, Int, Bool)] = []
        while i > 0, j > 0 {
            let same = Self.same(script[i - 1], heard[j - 1])
            if dp[i][j] == dp[i - 1][j - 1] + (same ? 2 : -1) {
                pairs.append((i - 1, j - 1, same))
                i -= 1; j -= 1
            } else if dp[i][j] == dp[i - 1][j] - 1 {
                i -= 1
            } else {
                j -= 1
            }
        }
        pairs.reverse()
        // Trim substitutions at the edges: they're neighbouring words, not this sentence.
        while let first = pairs.first, !first.2 { pairs.removeFirst() }
        while let last = pairs.last, !last.2 { pairs.removeLast() }
        guard let first = pairs.first else { return nil }
        return (first.1, pairs)
    }
}
