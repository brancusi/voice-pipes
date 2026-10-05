import Foundation

/// Sentences to read when training a word, written by an LLM for that word, so they read naturally and use it in the
/// sense it has for you. Your other vocabulary only tells the model what you mean (a programmer's TUI is a terminal
/// user interface, not the travel company); sentences that use those words anyway are dropped, since they could be
/// misheard too. Without an OpenRouter key, or if the call fails, the built-in sentences are used.
/// Measured 2026-10-05 with Claude Haiku 4.5: about 2 s, every sentence contained the term exactly.
enum TrainingSentences {
    static let model = "anthropic/claude-haiku-4.5"
    static let count = 6

    static let system = """
        You write practice sentences for training speech recognition on one term. The person reads each sentence out \
        loud, the way they'd dictate an email, a chat message or a note. Make them easy and natural to say: plain, \
        conversational, 8 to 14 words, something this person would really say, with no other names, brands or jargon \
        besides the term. Use the term in the meaning it has for this person; their other vocabulary is given only so \
        you can tell what they mean (a programmer's TUI is a terminal user interface), so never put those other words \
        in the sentences. Every sentence contains the term exactly as given (same spelling and capitals), once. Vary \
        where it falls: start, middle, end. Reply with only a JSON array of 8 strings.
        """

    static var available: Bool { Keychain.get(SecretKey.openRouter) != nil }

    /// `hint`: what the term is, in the user's words (optional). `vocabulary`: their other terms, for context.
    static func make(term: String, hint: String, vocabulary: [String]) async throws -> [String] {
        let others = vocabulary.filter { $0.caseInsensitiveCompare(term) != .orderedSame }
        var user = "Term: \(term)\n"
        if !hint.trimmingCharacters(in: .whitespaces).isEmpty { user += "What it is: \(hint)\n" }
        if !others.isEmpty { user += "Their other vocabulary: \(others.joined(separator: ", "))" }
        let reply = try await OpenRouterClient.shared.complete(model: model, system: system, user: user)
        return valid(parse(reply), term: term, others: others)
    }

    /// The JSON array in the reply (models sometimes wrap it in a code fence or a line of text).
    static func parse(_ reply: String) -> [String] {
        guard let start = reply.firstIndex(of: "["), let end = reply.lastIndex(of: "]"), start < end,
              let array = try? JSONDecoder().decode([String].self, from: Data(reply[start...end].utf8)) else { return [] }
        return array
    }

    /// Sentences that contain the term exactly once, are a sayable length, and don't use another vocabulary term
    /// (only terms with a capital or a digit count: "want to" is ordinary language). Up to `count`.
    static func valid(_ sentences: [String], term: String, others: [String]) -> [String] {
        let distinctive = others.filter { $0.contains(where: { $0.isUppercase || $0.isNumber }) }
        var seen = Set<String>()
        return Array(sentences.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { s in
            let words = s.split(separator: " ").count
            return s.components(separatedBy: term).count == 2 && (5...20).contains(words)
                && !distinctive.contains { s.range(of: $0, options: .caseInsensitive) != nil }
                && seen.insert(s).inserted
        }.prefix(count))
    }
}
