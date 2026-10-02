import AppKit
import CryptoKit
import Foundation
import Network

/// Sign in with OpenRouter (OAuth PKCE): opens the browser, catches the redirect on a one-time localhost port (loopback
/// only), and exchanges the code for a key labelled "Voice Pipes". Headless mode (SSH, no browser here) returns the
/// URL to open elsewhere; OpenRouter then shows a code, and a second call with `code` finishes.
@MainActor
final class OpenRouterLogin {
    static let shared = OpenRouterLogin()
    /// The verifier from a headless start, kept until its code comes back (codes expire after 10 minutes).
    private var pendingVerifier: (String, Date)?

    /// The key, or nil when a headless login is waiting for its code.
    func run(headless: Bool, code: String?, announce: @escaping (URL) -> Void) async throws -> String? {
        if let code {
            guard let (verifier, started) = pendingVerifier, Date().timeIntervalSince(started) < 600 else {
                throw AgentError("no_pending_login", "No headless login is waiting, or it expired.", hint: "vp auth login openrouter --headless")
            }
            pendingVerifier = nil
            return try await exchange(code: code, verifier: verifier)
        }
        let verifier = Self.randomVerifier()
        let challenge = Self.challenge(for: verifier)
        if headless {
            pendingVerifier = (verifier, Date())
            announce(Self.authURL(challenge: challenge, callback: nil))
            return nil
        }
        let catcher = try CallbackCatcher()
        let port = try await catcher.start()
        let url = Self.authURL(challenge: challenge, callback: URL(string: "http://localhost:\(port)/callback")!)
        announce(url)
        NSWorkspace.shared.open(url)
        let code = try await catcher.code(timeout: 300)
        return try await exchange(code: code, verifier: verifier)
    }

    private static func authURL(challenge: String, callback: URL?) -> URL {
        var components = URLComponents(string: "https://openrouter.ai/auth")!
        components.queryItems = [URLQueryItem(name: "code_challenge", value: challenge),
                                 URLQueryItem(name: "code_challenge_method", value: "S256"),
                                 URLQueryItem(name: "key_label", value: "Voice Pipes")]
            + (callback.map { [URLQueryItem(name: "callback_url", value: $0.absoluteString)] } ?? [])
        return components.url!
    }

    private func exchange(code: String, verifier: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/auth/keys")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["code": code, "code_verifier": verifier, "code_challenge_method": "S256"])
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status), let key = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["key"] as? String else {
            let detail = String(data: data, encoding: .utf8) ?? ""
            throw AgentError("login_failed", "OpenRouter didn't issue a key (HTTP \(status)). \(detail.prefix(200))",
                             hint: "Try again: vp auth login openrouter")
        }
        return key
    }

    static func randomVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 48)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URL
    }

    static func challenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
    }
}

extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// A one-shot HTTP listener on a free loopback port that waits for `GET /callback?code=…`.
private final class CallbackCatcher: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "VoicePipes.oauth")
    private var continuation: CheckedContinuation<String, Error>?
    private var finished = false
    private var readyResumed = false

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        parameters.allowLocalEndpointReuse = true
        listener = try NWListener(using: parameters, on: .any)
    }

    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { (ready: CheckedContinuation<UInt16, Error>) in
            // The handler runs on `queue` only, so `readyResumed` needs no lock.
            listener.stateUpdateHandler = { [weak self] state in
                guard let self, !self.readyResumed else { return }
                switch state {
                case .ready:
                    self.readyResumed = true
                    ready.resume(returning: self.listener.port?.rawValue ?? 0)
                case .failed(let error):
                    self.readyResumed = true
                    ready.resume(throwing: error)
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in self?.serve(connection) }
            listener.start(queue: queue)
        }
    }

    func code(timeout: TimeInterval) async throws -> String {
        defer { listener.cancel() }
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.continuation = continuation
                self.queue.asyncAfter(deadline: .now() + timeout) {
                    self.finish(.failure(AgentError("login_timeout", "No answer from the browser within \(Int(timeout / 60)) minutes.",
                                                    hint: "vp auth login openrouter (or --headless on a machine without a browser)")))
                }
            }
        }
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            guard let self else { return }
            let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let target = request.split(separator: " ").dropFirst().first.map(String.init) ?? ""
            let code = URLComponents(string: "http://localhost" + target)?.queryItems?.first { $0.name == "code" }?.value
            let page = code == nil
                ? "<p>Voice Pipes didn't get a code from OpenRouter. Run <code>vp auth login openrouter</code> again.</p>"
                : "<p>Voice Pipes is signed in to OpenRouter. You can close this tab.</p>"
            let body = "<!doctype html><meta charset=utf-8><title>Voice Pipes</title><body style=\"font:15px ui-monospace,monospace;background:#1f1a15;color:#f0e4cc;padding:48px\">\(page)</body>"
            let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
            if target.hasPrefix("/callback") {
                self.finish(code.map { .success($0) } ?? .failure(AgentError("login_failed", "OpenRouter sent no code.")))
            }
        }
    }

    private func finish(_ result: Result<String, Error>) {
        guard !finished, let continuation else { return }
        finished = true
        continuation.resume(with: result)
    }
}
