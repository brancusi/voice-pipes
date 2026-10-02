import Foundation

/// TypeSafe's Jev: a fast structured-decision model (https://docs.typesafe.ai/api). Used when training vocabulary,
/// to judge whether each mishearing is safe to replace everywhere, and by Route steps to pick a model for the input.
final class JevClient: Sendable {
    static let shared = JevClient()

    private let endpoint = URL(string: "https://api.typesafe.ai/v1/systemone")!
    private let batchSize = 25

    static var hasKey: Bool { Keychain.get(SecretKey.typesafe) != nil }

    /// Probability (0…1) that each candidate should always be replaced with `target`.
    func judgeReplacements(target: String, candidates: [String]) async throws -> [String: Double] {
        guard let key = Keychain.get(SecretKey.typesafe), !key.isEmpty else { throw JevError.missingKey }
        let batches = stride(from: 0, to: candidates.count, by: batchSize).map {
            Array(candidates[$0..<min($0 + batchSize, candidates.count)])
        }
        return try await withThrowingTaskGroup(of: [String: Double].self) { group in
            for batch in batches {
                group.addTask { try await self.judge(target: target, candidates: batch, key: key) }
            }
            var all: [String: Double] = [:]
            for try await part in group { all.merge(part) { a, _ in a } }
            return all
        }
    }

    private func judge(target: String, candidates: [String], key: String) async throws -> [String: Double] {
        let question = """
            Speech recognition heard someone say `target` and wrote `candidate` instead. A replacement rule would \
            rewrite every occurrence of `candidate` as `target` in everything this person dictates: emails, chat, \
            notes and code. Should `candidate` be replaced?
            """
        var questions: [String: Any] = [:]
        for (i, candidate) in candidates.enumerated() {
            questions["c\(i)"] = [
                "type": "noul",
                "instructions": ["target": target, "candidate": candidate, "question": question],
                "criteria": [
                    "true": "`candidate` is a garbled transcription of `target`: not a real word or phrase, name, product, code identifier or term someone would intentionally write, so replacing it is safe.",
                    "false": "`candidate` is (or contains as a whole) ordinary language, a different real name, or a term used in coding or another field, so replacing it could change text the person meant.",
                ],
            ]
        }
        let body: [String: Any] = [
            "model": "jev-latest",
            "state": ["task": "Building a personal dictation vocabulary of automatic spelling corrections.", "target": target],
            "questions": questions,
        ]
        struct Answer: Decodable { let noul: Double? }
        struct Response: Decodable { let answers: [String: Answer] }
        let answers = try JSONDecoder().decode(Response.self, from: try await post(body, key: key)).answers
        var result: [String: Double] = [:]
        for (i, candidate) in candidates.enumerated() {
            if let p = answers["c\(i)"]?.noul { result[candidate] = p }
        }
        return result
    }

    /// Picks the route for `input` (a Route step): returns the chosen route's index and its probability.
    func chooseRoute(input: String, routes: [Route]) async throws -> (index: Int, probability: Double) {
        guard let key = Keychain.get(SecretKey.typesafe), !key.isEmpty else { throw JevError.missingKey }
        // Option names are what Jev sees, so keep the route names, made unique and non-empty.
        var options: [String] = []
        for (i, route) in routes.enumerated() {
            let name = route.name.trimmingCharacters(in: .whitespaces)
            options.append(name.isEmpty || options.contains(name) ? "route \(i + 1)" : name)
        }
        var criteria: [String: Any] = [:]
        for (option, route) in zip(options, routes) {
            criteria[option] = route.when.isEmpty ? NSNull() : route.when as Any
        }
        let body: [String: Any] = [
            "model": "jev-latest",
            "state": ["input": input],
            "questions": ["route": [
                "type": "choice",
                "instructions": "Someone dictated `input` and a language model will respond to it. Which route should handle it?",
                "criteria": criteria,
            ]],
        ]
        struct Answer: Decodable { let choice: String; let probabilities: [String: Double] }
        struct Response: Decodable { let answers: [String: Answer] }
        guard let answer = try JSONDecoder().decode(Response.self, from: try await post(body, key: key)).answers["route"],
              let index = options.firstIndex(of: answer.choice) else { throw JevError.http(200, "No route in Jev's answer") }
        return (index, answer.probabilities[answer.choice] ?? 0)
    }

    /// Picks one of `options` (name, what it's for) for `input`, answering `question` (a Branch block): the index
    /// and its probability.
    func choose(input: String, question: String?, options: [(name: String, when: String)]) async throws -> (index: Int, probability: Double) {
        guard let key = Keychain.get(SecretKey.typesafe), !key.isEmpty else { throw JevError.missingKey }
        var names: [String] = []
        for (i, option) in options.enumerated() {
            let name = option.name.trimmingCharacters(in: .whitespaces)
            names.append(name.isEmpty || names.contains(name) ? "branch \(i + 1)" : name)
        }
        var criteria: [String: Any] = [:]
        for (name, option) in zip(names, options) { criteria[name] = option.when.isEmpty ? NSNull() : option.when as Any }
        let asked = question?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let body: [String: Any] = [
            "model": "jev-latest",
            "state": ["input": input],
            "questions": ["branch": [
                "type": "choice",
                "instructions": "`input` is text at this point in a voice pipeline."
                    + (asked.isEmpty ? "" : " Question: \(asked)") + " Pick the branch that should handle it.",
                "criteria": criteria,
            ]],
        ]
        struct Answer: Decodable { let choice: String; let probabilities: [String: Double] }
        struct Response: Decodable { let answers: [String: Answer] }
        guard let answer = try JSONDecoder().decode(Response.self, from: try await post(body, key: key)).answers["branch"],
              let index = names.firstIndex(of: answer.choice) else { throw JevError.http(200, "No branch in Jev's answer") }
        return (index, answer.probabilities[answer.choice] ?? 0)
    }

    private func post(_ body: [String: Any], key: String) async throws -> Data {
        var request = URLRequest(url: endpoint, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        // Back off and retry on rate limits and overload, as the API docs ask.
        for attempt in 0..<4 {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            switch status {
            case 200:
                return data
            case 401, 403:
                throw JevError.rejectedKey
            case 429, 529:
                try await Task.sleep(for: .milliseconds(400 * (1 << attempt)))
            default:
                throw JevError.http(status, String(data: data, encoding: .utf8) ?? "")
            }
        }
        throw JevError.http(429, "Still rate limited after retries")
    }
}

enum JevError: LocalizedError {
    case missingKey, rejectedKey
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingKey: "No TypeSafe (Jev) key. Add one in Setup."
        case .rejectedKey: "TypeSafe rejected the Jev key. Check it in Setup."
        case .http(let code, let body): "Jev error \(code): \(body.prefix(200))"
        }
    }
}
