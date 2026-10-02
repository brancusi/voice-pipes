import Foundation

/// What the model pickers say about a model: what a typical job costs, how fast it is on this Mac, how good it is,
/// and how it ranks. Never guessed: a price is used only in a billing unit we know, speeds are measured from your
/// runs (or our own benchmark for on-device models), and quality comes from Resources/model-ratings.json, a curated
/// snapshot of public leaderboards with its sources. Missing data stays missing ("—", "not rated").
@MainActor
enum ModelInsights {
    // MARK: Ratings (curated per release)

    struct Ratings: Decodable {
        struct Source: Decodable { let name: String; let url: String?; let date: String? }
        struct Rating: Decodable {
            /// 1…5.
            let score: Int?
            /// The leaderboard's own number (Elo, WER %, Intelligence Index), for the record.
            let raw: Double?
            let tags: [String]?
            let sentence: String?
            /// Billing unit when the catalogue's is ambiguous: char | second | hour | token | request.
            let unit: String?
            /// Our own benchmark on this Mac (on-device models), until there are runs.
            let benchmarkMs: Int?
        }
        let sources: [String: Source]
        let models: [String: Rating]
    }

    static let ratings: Ratings = {
        var urls = [Bundle.main.url(forResource: "model-ratings", withExtension: "json")]
        #if SNAPSHOTS
        urls.append(URL(fileURLWithPath: "/path/to/voice-pipes/Resources/model-ratings.json"))
        #endif
        for url in urls.compactMap({ $0 }) {
            if let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode(Ratings.self, from: data) { return decoded }
        }
        return Ratings(sources: [:], models: [:])
    }()

    static func sourceKey(_ capability: OpenRouterCatalog.Capability) -> String {
        switch capability {
        case .speech: "speech"
        case .transcription: "transcription"
        case .text: "text"
        }
    }

    // MARK: A typical job ("a paragraph")

    /// Speak: 600 characters (~40 s of audio). LLM: 150 tokens in + 150 out. Transcribe: 30 s of audio.
    static func paragraphCost(_ id: String, _ capability: OpenRouterCatalog.Capability) -> Double? {
        if id.hasPrefix("local:") { return 0 }
        guard let model = OpenRouterCatalog.shared.model(id), let pricing = model.pricing else { return nil }
        let prompt = pricing.prompt.flatMap(Double.init) ?? 0, completion = pricing.completion.flatMap(Double.init) ?? 0
        let request = pricing.request.flatMap(Double.init) ?? 0
        if prompt == 0, completion == 0 { return request }
        let unit = ratings.models[id]?.unit
        switch capability {
        case .text:
            return 150 * prompt + 150 * completion + request
        case .speech:
            // Per character when only the input is priced; anything else needs a curated unit.
            if unit == "char" || (unit == nil && completion == 0) { return 600 * prompt + request }
            if unit == "second" { return 40 * (completion > 0 ? completion : prompt) + request }
            return nil
        case .transcription:
            // Per second, except a few priced per hour (no real per-second price is a cent or more).
            if let measured = measuredCostPerSecond(id) { return 30 * measured }
            guard completion == 0, unit != "token" else { return nil }
            if unit == "hour" || (unit == nil && prompt >= 0.01) { return 30 * prompt / 3600 + request }
            return 30 * prompt + request
        }
    }

    /// Exact cost per second of audio from your own transcription runs (OpenRouter reports it), when there are any.
    static func measuredCostPerSecond(_ id: String) -> Double? {
        let samples = recentEntries(id).compactMap { e -> Double? in
            guard let u = e.usage, let cost = u.cost, let seconds = u.seconds, seconds > 0, u.estimated != true else { return nil }
            return cost / seconds
        }
        return samples.isEmpty ? nil : samples.reduce(0, +) / Double(samples.count)
    }

    // MARK: Speed, measured on this Mac

    /// Median of your last 20 runs of the model: first sound (Speak), reply time (LLM), time to text (Transcribe).
    static func measuredMs(_ id: String, _ capability: OpenRouterCatalog.Capability) -> Int? {
        let values = recentEntries(id).compactMap { e -> Int? in
            switch capability {
            case .speech: return e.firstSoundMs
            case .text:
                let ms = e.decision.map { e.ms - $0.jevMs } ?? e.ms  // a Route's own time includes Jev's pick
                return ms > 0 ? ms : nil
            case .transcription: return e.ms > 0 && e.message == nil ? e.ms : nil
            }
        }.prefix(20).sorted()
        guard !values.isEmpty else { return nil }
        return values[values.count / 2]
    }

    /// Log entries for a model, newest first (History keeps the newest first).
    private static func recentEntries(_ id: String) -> [RunRecord.LogEntry] {
        (historyStore?.records ?? []).flatMap { ($0.log ?? []).filter { $0.model == id && $0.status == .ok } }
    }

    /// History, set by AppState at launch.
    static weak var historyStore: HistoryStore?

    // MARK: Ranking

    enum Sort: String, CaseIterable { case value, quality, speed, cost }

    struct Info {
        var cost: Double?
        var costFromRuns = false
        var ms: Int?
        var msIsBenchmark = false
        var quality: Int?
        /// The leaderboard's own number, to order models within the same 1–5 bucket (higher = better).
        var qualityDetail: Double?
        var tags: [String] = []
        var sentence: String?
    }

    static func info(_ id: String, _ capability: OpenRouterCatalog.Capability) -> Info {
        let rating = ratings.models[id]
        var info = Info()
        info.cost = paragraphCost(id, capability)
        info.costFromRuns = capability == .transcription && measuredCostPerSecond(id) != nil
        if let measured = measuredMs(id, capability) {
            info.ms = measured
        } else if let bench = rating?.benchmarkMs {
            info.ms = bench
            info.msIsBenchmark = true
        }
        info.quality = rating?.score
        // Word error rate: lower is better, so flip it for ordering.
        info.qualityDetail = rating?.raw.map { capability == .transcription ? -$0 : $0 }
        // Tags say what the columns can't: what it can do. Free tiers are rate-limited; vision when it reads images.
        var tags: [String] = []
        if id.hasSuffix(":free") { tags.append("rate-limited") }
        tags += rating?.tags ?? []
        if capability == .text, OpenRouterCatalog.shared.model(id)?.inputs.contains("image") == true, !tags.contains("vision") { tags.append("vision") }
        info.tags = Array(tags.prefix(2))
        info.sentence = rating?.sentence
        return info
    }

    /// Best value, in one place to tune: quality over log-scaled cost, plus a bonus for free models. Needs both a
    /// rating and a known cost; without either there's no value (unknown cost ranks after every known one).
    static func value(_ info: Info) -> Double? {
        guard let quality = info.quality, let cost = info.cost else { return nil }
        let costPenalty = log10(1 + cost * 10_000)  // $0 → 0, $0.0001 → 0.3, $0.001 → 1.04, $0.01 → 2.0, $0.1 → 3.0
        return Double(quality) / (1 + costPenalty) + (cost == 0 ? 0.5 : 0)
    }

    /// Orders ids for a sort. Missing data sinks: on Best value, rated models with a known cost first, then rated
    /// ones with an unknown cost (in quality order), then unrated; unrated sort by speed among themselves (that's
    /// how the On this Mac group orders).
    static func order(_ ids: [String], _ capability: OpenRouterCatalog.Capability, by sort: Sort) -> [String] {
        let infos = Dictionary(uniqueKeysWithValues: ids.map { ($0, info($0, capability)) })
        func quality(_ i: Info) -> Double? { i.quality.map { -Double($0) * 1_000_000 - (i.qualityDetail ?? 0) } }
        /// (tier, key): a lower tier comes first; within it, a lower key.
        func rank(_ id: String) -> (Int, Double) {
            let i = infos[id]!
            let speed = i.ms.map(Double.init) ?? .infinity
            switch sort {
            case .value:
                if let v = value(i) { return (0, -v) }
                if let q = quality(i) { return (1, q) }
                return (2, speed)
            case .quality:
                return quality(i).map { (0, $0) } ?? (1, speed)
            case .speed:
                return i.ms.map { (0, Double($0)) } ?? (1, 0)
            case .cost:
                return i.cost.map { (0, $0) } ?? (1, 0)
            }
        }
        return ids.enumerated().sorted { a, b in
            let x = rank(a.element), y = rank(b.element)
            return x != y ? x < y : a.offset < b.offset
        }.map(\.element)
    }
}
