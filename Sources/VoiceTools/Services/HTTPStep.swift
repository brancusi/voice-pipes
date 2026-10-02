import Foundation

/// Generic REST step. `{{input}}` in the URL or body is replaced with the text; `{{input_json}}`
/// with the text as a JSON string literal (quoted and escaped).
enum HTTPStep {
    static func run(input: String, url: String, method: String, headers: [String: String],
                    bodyTemplate: String, responseField: String) async throws -> String {
        let encodedInput = input.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? input
        // ${secret:name} (Keychain, `vp secret set`) and ${env:NAME}, resolved only now, never stored in the config.
        let template = url
        let url = Secrets.interpolate(url)
        let headers = headers.mapValues(Secrets.interpolate)
        let bodyTemplate = Secrets.interpolate(bodyTemplate)
        guard let requestURL = URL(string: url.replacingOccurrences(of: "{{input}}", with: encodedInput)) else {
            throw HTTPStepError.badURL(template)  // as written: the resolved one may hold a secret
        }
        var request = URLRequest(url: requestURL)
        request.httpMethod = method
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        if method != "GET", !bodyTemplate.isEmpty {
            request.httpBody = Data(Template.render(bodyTemplate, input: input).utf8)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw HTTPStepError.status(http.statusCode)
        }
        let text = String(data: data, encoding: .utf8) ?? ""
        guard !responseField.isEmpty else { return text }

        // Dotted path into a JSON response, e.g. "data.text".
        var value: Any? = try? JSONSerialization.jsonObject(with: data)
        for key in responseField.split(separator: ".") {
            value = (value as? [String: Any])?[String(key)]
        }
        return (value as? String) ?? text
    }
}

enum Template {
    static func render(_ template: String, input: String) -> String {
        let json = (try? JSONEncoder().encode(input)).flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
        return template
            .replacingOccurrences(of: "{{input_json}}", with: json)
            .replacingOccurrences(of: "{{input}}", with: input)
    }
}

enum HTTPStepError: LocalizedError {
    case badURL(String)
    case status(Int)

    var errorDescription: String? {
        switch self {
        case .badURL(let url): "Invalid URL: \(url)"
        case .status(let code): "HTTP step failed with status \(code)"
        }
    }
}
