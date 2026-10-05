import Foundation

/// Finds what transcription wrote for one term in a sentence that was read aloud, without letting the rest of the
/// sentence leak in. The transcript is aligned word by word with the sentence (longest common subsequence), and the
/// term's span is what lies between the nearest correctly heard words on either side of it. A stumble, a filler or a
/// misread word elsewhere in the sentence doesn't move those anchors. When the anchors aren't right next to the term
/// (its neighbours were misheard too, so they'd sit in the span) or most of the sentence came out wrong, the take is
/// rejected (nil) rather than guessed at: a missed result costs less than a false one in the Fix words list.
enum SpanAligner {
    /// Words that end up in a span when someone hesitates; trimmed from its ends.
    static let fillers: Set<String> = ["uh", "um", "er", "erm", "ah", "eh", "hmm", "mm", "like"]

    enum Result: Equatable {
        /// The term was heard as written.
        case correct
        /// The term was heard as this instead.
        case heard(String)
        /// The take can't be trusted for this term.
        case rejected(String)
    }

    /// `sentence` and `term` as written; `transcript` as heard. All are compared after `normalize`.
    static func span(of term: String, in transcript: String, sentence: String, normalize: (String) -> String) -> Result {
        let s = normalize(sentence).split(separator: " ").map(String.init)
        let t = normalize(transcript).split(separator: " ").map(String.init)
        let w = normalize(term).split(separator: " ").map(String.init)
        guard !w.isEmpty, s.count >= w.count else { return .rejected("term not in sentence") }
        // Where the term sits in the sentence (allowing a possessive: "Aram Zadikian's").
        guard let at = (0...(s.count - w.count)).first(where: { i in
            zip(s[i..<i + w.count], w).allSatisfy { $0 == $1 || $0 == $1 + "'s" }
        }) else { return .rejected("term not in sentence") }
        let termRange = at..<(at + w.count)
        guard !t.isEmpty else { return .rejected("nothing heard") }

        // Align the words around the term only: the term's own words are what we're measuring.
        let pairs = lcs(s, t, skipping: termRange)
        let context = s.count - w.count
        if context > 0 {
            let matched = pairs.count
            // Most of the sentence misheard or misread: nothing in it can be trusted.
            guard Double(matched) / Double(context) >= 0.6 else { return .rejected("sentence mostly misheard (\(matched)/\(context))") }
        }

        // Anchors: the last matched sentence word before the term, the first one after it.
        let left = pairs.last { $0.s < termRange.lowerBound }
        let right = pairs.first { $0.s >= termRange.upperBound }
        // Unmatched sentence words between an anchor and the term would land in the span: allow none.
        let leftGap = termRange.lowerBound - ((left?.s ?? -1) + 1)
        let rightGap = (right?.s ?? s.count) - termRange.upperBound
        guard leftGap == 0, rightGap == 0 else { return .rejected("a word next to the term was misheard") }

        let from = (left?.t ?? -1) + 1, to = right?.t ?? t.count
        guard from <= to else { return .rejected("alignment crossed") }
        var span = Array(t[from..<to])
        while let first = span.first, fillers.contains(first) { span.removeFirst() }
        while let last = span.last, fillers.contains(last) { span.removeLast() }
        if let last = span.last, last.hasSuffix("'s"), s[termRange.upperBound - 1].hasSuffix("'s") {
            span[span.count - 1] = String(last.dropLast(2))
        }
        // A stutter ("code code") is the reader, not the transcription.
        span = span.enumerated().filter { $0.offset == 0 || $0.element != span[$0.offset - 1] }.map(\.element)
        guard !span.isEmpty else { return .rejected("term dropped") }
        // The term heard right with a word slipped in beside it ("a simple TUI app"): it was heard right.
        if span.count > w.count, (0...(span.count - w.count)).contains(where: { Array(span[$0..<$0 + w.count]) == w }) { return .correct }
        // A span much longer than the term is more than the term. At the start or end of the sentence there's no
        // anchor on that side, so anything said past the term would land in the span: allow less.
        let open = left == nil || right == nil
        guard span.count <= w.count + (open ? 1 : 2) else { return .rejected("span too long") }
        let heard = span.joined(separator: " ")
        return heard == w.joined(separator: " ") ? .correct : .heard(heard)
    }

    /// Longest common subsequence of word lists: matched (sentence index, transcript index) pairs, in order.
    /// Sentence words in `skipping` never match (the term itself).
    static func lcs(_ a: [String], _ b: [String], skipping: Range<Int>) -> [(s: Int, t: Int)] {
        let n = a.count, m = b.count
        var table = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                table[i][j] = !skipping.contains(i) && a[i] == b[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
            }
        }
        var pairs: [(Int, Int)] = []
        var i = 0, j = 0
        while i < n, j < m {
            if !skipping.contains(i), a[i] == b[j], table[i][j] == table[i + 1][j + 1] + 1 {
                pairs.append((i, j)); i += 1; j += 1
            } else if table[i + 1][j] >= table[i][j + 1] {
                i += 1
            } else {
                j += 1
            }
        }
        return pairs.map { (s: $0.0, t: $0.1) }
    }
}
