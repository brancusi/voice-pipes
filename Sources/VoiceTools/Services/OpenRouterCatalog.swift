import Foundation
import Observation

/// OpenRouter's model list, for the model and voice pickers. Fetched from the public models API, cached on disk,
/// and refreshed once a day (or on demand).
@MainActor
@Observable
final class OpenRouterCatalog {
    static let shared = OpenRouterCatalog()

    /// What a step needs a model to do.
    enum Capability: String {
        case transcription, text, speech

        var title: String {
            switch self {
            case .transcription: "Transcription models"
            case .text: "Language models"
            case .speech: "Speech models"
            }
        }
    }

    struct Model: Codable, Identifiable, Hashable {
        struct Architecture: Codable, Hashable {
            var input_modalities: [String]?
            var output_modalities: [String]?
        }

        struct Pricing: Codable, Hashable {
            var prompt: String?
            var completion: String?
        }

        let id: String
        let name: String
        var description: String?
        var context_length: Int?
        var architecture: Architecture?
        var pricing: Pricing?
        var supported_voices: [String]?

        var outputs: [String] { architecture?.output_modalities ?? [] }
        var inputs: [String] { architecture?.input_modalities ?? [] }
        var voices: [String] { supported_voices ?? [] }

        /// The provider's name shown in OpenRouter's titles ("Microsoft AI: MAI-Voice-2.1") is dropped for lists.
        var shortName: String {
            name.split(separator: ":", maxSplits: 1).last.map { $0.trimmingCharacters(in: .whitespaces) } ?? name
        }

        var provider: String { id.split(separator: "/").first.map(String.init) ?? "" }

        func supports(_ capability: Capability) -> Bool {
            switch capability {
            case .transcription: outputs.contains("transcription")
            case .speech: outputs.contains("speech")
            case .text: outputs.contains("text") && inputs.contains("text") && !outputs.contains("transcription")
            }
        }

        /// Compact, for the picker chip: "$1/$5" (in/out per 1M tokens), "$15/1M ch", "free".
        func shortPrice(for capability: Capability) -> String? {
            func perMillion(_ value: String?) -> String? {
                guard let value, let v = Double(value), v > 0 else { return nil }
                let cents = (v * 1_000_000 * 100).rounded() / 100
                if cents == 0 { return "<$0.01" }
                return cents == cents.rounded() ? String(format: "$%.0f", cents) : String(format: "$%.2f", cents)
            }
            switch capability {
            case .speech:
                if let chars = perMillion(pricing?.prompt) { return "\(chars)/1M ch" }
                return pricing == nil ? nil : "free"
            case .text, .transcription:
                let input = perMillion(pricing?.prompt), output = perMillion(pricing?.completion)
                if input == nil, output == nil { return pricing == nil ? nil : "free" }
                return "\(input ?? "$0")/\(output ?? "$0")"
            }
        }

        func priceLabel(for capability: Capability) -> String {
            func perMillion(_ value: String?) -> String? {
                guard let value, let v = Double(value), v > 0 else { return nil }
                let m = v * 1_000_000
                return m >= 10 ? String(format: "$%.0f", m) : m >= 1 ? String(format: "$%.2f", m) : String(format: "$%.3f", m)
            }
            switch capability {
            case .speech:
                if let chars = perMillion(pricing?.prompt) { return "\(chars) / 1M chars" }
                if let v = pricing?.completion, let s = Double(v), s > 0 { return String(format: "$%.4f / s", s) }
                return "free"
            case .text, .transcription:
                let input = perMillion(pricing?.prompt), output = perMillion(pricing?.completion)
                if input == nil, output == nil { return "free" }
                return "\(input ?? "$0") in · \(output ?? "$0") out / 1M"
            }
        }
    }

    private(set) var models: [Model] = []
    private(set) var loading = false
    private(set) var error: String?
    private(set) var updated: Date?

    private let cacheURL = TrackStore.defaultURL.deletingLastPathComponent().appendingPathComponent("models-cache.json")

    private init() {
        if let data = try? Data(contentsOf: cacheURL),
           let cached = try? JSONDecoder().decode(Cache.self, from: data) {
            models = cached.models
            updated = cached.updated
        }
    }

    nonisolated private static func fetch(_ query: String) async throws -> [Model] {
        struct Response: Decodable { let data: [Model] }
        let url = URL(string: "https://openrouter.ai/api/v1/models\(query)")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(Response.self, from: data).data
    }

    private struct Cache: Codable {
        var updated: Date
        var models: [Model]
    }

    func models(for capability: Capability) -> [Model] {
        models.filter { $0.supports(capability) }
    }

    func model(_ id: String) -> Model? { models.first { $0.id == id } }

    /// Loads the list if it's missing or older than a day.
    func refreshIfStale() {
        if models.isEmpty || (updated.map { Date().timeIntervalSince($0) > 86_400 } ?? true) { refresh() }
    }

    func refresh() {
        guard !loading else { return }
        loading = true
        error = nil
        Task {
            defer { loading = false }
            do {
                // The default list only has language models; speech and transcription models are listed
                // only when asked for by output modality.
                async let text = Self.fetch("")
                async let speech = Self.fetch("?output_modalities=speech")
                async let transcription = Self.fetch("?output_modalities=transcription")
                var byID: [String: Model] = [:]
                for model in try await text + speech + transcription { byID[model.id] = model }
                models = byID.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                updated = Date()
                if let encoded = try? JSONEncoder().encode(Cache(updated: Date(), models: models)) {
                    try? encoded.write(to: cacheURL, options: .atomic)
                }
            } catch {
                self.error = "Couldn't load OpenRouter's models: \(error.localizedDescription)"
            }
        }
    }
}

extension OpenRouterCatalog.Model {
    /// A friendlier label for a voice id: "en-US-Harper:MAI-Voice-2.1" → "Harper (en-US)",
    /// "aura-2-thalia-en" → "Thalia (en)", "English_expressive_narrator" → "Expressive narrator (English)".
    static func voiceLabel(_ id: String) -> String {
        let base = id.split(separator: ":").first.map(String.init) ?? id
        let parts = base.split(separator: "-").map(String.init)
        if parts.count >= 3, parts[0].count == 2, parts[1].count == 2 {
            return "\(parts[2...].joined(separator: " ")) (\(parts[0])-\(parts[1]))"
        }
        if base.hasPrefix("aura-2-"), parts.count >= 4 {
            return "\(parts[2].capitalized) (\(parts[3]))"
        }
        let underscored = base.split(separator: "_").map(String.init)
        if underscored.count >= 2, underscored[0].count == 2, underscored[0] == underscored[0].lowercased() {
            // "en_paul_neutral" → "Paul neutral (en)", "af_bella" → "Bella (af)"
            let rest = underscored[1...].joined(separator: " ")
            return "\(rest.prefix(1).uppercased() + rest.dropFirst()) (\(underscored[0]))"
        }
        if underscored.count >= 2, underscored[0].first?.isUppercase == true {
            let rest = underscored[1...].joined(separator: " ")
            return "\(rest.prefix(1).uppercased() + rest.dropFirst()) (\(underscored[0]))"
        }
        return base
    }

    /// Voices with English ones first, otherwise in the provider's order.
    var voicesEnglishFirst: [String] {
        let english = voices.filter(Self.isEnglish)
        return english + voices.filter { !Self.isEnglish($0) }
    }

    static func isEnglish(_ voice: String) -> Bool {
        let v = voice.lowercased()
        return v.hasPrefix("en-") || v.hasPrefix("en_") || v.hasSuffix("-en") || v.hasPrefix("english")
            || v.hasPrefix("af_") || v.hasPrefix("am_") || v.hasPrefix("bf_") || v.hasPrefix("bm_")
    }

    /// The voice to pick when switching to this model: English if there is one.
    var defaultVoice: String? {
        voices.first { $0.hasPrefix("en-US") }
            ?? voices.first { let v = $0.lowercased(); return v.hasSuffix("-en") || v.hasPrefix("en_") || v.hasPrefix("english") }
            ?? voices.first
    }
}
