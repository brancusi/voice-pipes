import Foundation

/// TypeSafe's Jev: a fast structured-decision model (https://docs.typesafe.ai/api). Used when training vocabulary,
/// to judge whether each mishearing is safe to replace everywhere, or is something people actually write.
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
                struct Answer: Decodable { let noul: Double? }
                struct Response: Decodable { let answers: [String: Answer] }
                let answers = try JSONDecoder().decode(Response.self, from: data).answers
                var result: [String: Double] = [:]
                for (i, candidate) in candidates.enumerated() {
                    if let p = answers["c\(i)"]?.noul { result[candidate] = p }
                }
                return result
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
