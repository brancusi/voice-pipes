import Foundation

/// Minimal OpenRouter client: transcription and chat completions over one shared, kept-alive session.
final class OpenRouterClient: Sendable {
    static let shared = OpenRouterClient()

    private let base = URL(string: "https://openrouter.ai/api/v1/")!
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: config)
    }()

    private var apiKey: String {
        get throws {
            guard let key = Keychain.get(SecretKey.openRouter), !key.isEmpty else { throw OpenRouterError.missingKey }
            return key
        }
    }

    /// Opens the TLS connection ahead of time (called when recording starts) so the real upload doesn't pay for it.
    func prewarm() {
        guard let key = try? apiKey else { return }
        var request = URLRequest(url: base.appendingPathComponent("key"))
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        session.dataTask(with: request).resume()
    }

    func transcribe(wav: Data, model: String) async throws -> String {
        let boundary = "vt-\(UUID().uuidString)"
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n")
        }
        field("model", model)
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n")
        body.append("Content-Type: audio/wav\r\n\r\n")
        body.append(wav)
        body.append("\r\n--\(boundary)--\r\n")

        var request = URLRequest(url: base.appendingPathComponent("audio/transcriptions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(try apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        struct Response: Decodable { let text: String }
        return try await send(request, as: Response.self).text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func complete(model: String, system: String?, user: String) async throws -> String {
        struct Message: Codable { let role: String; let content: String }
        struct Request: Encodable { let model: String; let messages: [Message] }
        struct Response: Decodable {
            struct Choice: Decodable { let message: Message }
            let choices: [Choice]
        }
        var messages: [Message] = []
        if let system, !system.isEmpty { messages.append(Message(role: "system", content: system)) }
        messages.append(Message(role: "user", content: user))

        var request = URLRequest(url: base.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(try apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Request(model: model, messages: messages))

        let response = try await send(request, as: Response.self)
        guard let text = response.choices.first?.message.content else { throw OpenRouterError.emptyResponse }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func send<T: Decodable>(_ request: URLRequest, as: T.Type) async throws -> T {
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw OpenRouterError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

enum OpenRouterError: LocalizedError {
    case missingKey
    case emptyResponse
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingKey: "No OpenRouter API key. Add one in Tracks → Connections."
        case .emptyResponse: "OpenRouter returned an empty response."
        case .http(let code, let body): "OpenRouter error \(code): \(body.prefix(300))"
        }
    }
}

extension Data {
    mutating func append(_ string: String) { append(Data(string.utf8)) }
}
