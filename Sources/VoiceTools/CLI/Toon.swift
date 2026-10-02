import Foundation

/// Output for agents (axi.md): TOON by default, JSON with --json.
/// TOON: `key: value`, nested objects indented, lists of uniform rows as `name[N]{a,b}:` then `v1,v2` lines,
/// lists of scalars as `name[N]: a,b`. Strings are quoted only when they'd be ambiguous.
indirect enum Out {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
    case object([(String, Out)])
    case list([Out])
    /// Rows with these fields, in this order.
    case table([String], [[Out]])

    static func s(_ v: String?) -> Out { v.map(Out.string) ?? .null }

    // MARK: TOON

    func toon(key: String? = nil, indent: Int = 0) -> String {
        let pad = String(repeating: "  ", count: indent)
        switch self {
        case .object(let pairs):
            let body = pairs.map { $0.1.toon(key: $0.0, indent: key == nil ? indent : indent + 1) }.joined(separator: "\n")
            guard let key else { return body }
            return pairs.isEmpty ? "\(pad)\(key): {}" : "\(pad)\(key):\n\(body)"
        case .list(let items):
            let label = "\(pad)\(key ?? "items")[\(items.count)]"
            if items.isEmpty { return label + ":" }
            if items.allSatisfy(\.isScalar) { return label + ": " + items.map(\.scalar).joined(separator: ",") }
            return label + ":\n" + items.map { $0.toon(key: "-", indent: indent + 1) }.joined(separator: "\n")
        case .table(let fields, let rows):
            let label = "\(pad)\(key ?? "rows")[\(rows.count)]{\(fields.joined(separator: ","))}:"
            return ([label] + rows.map { "\(pad)  " + $0.map(\.scalar).joined(separator: ",") }).joined(separator: "\n")
        default:
            return key.map { "\(pad)\($0): \(scalar)" } ?? "\(pad)\(scalar)"
        }
    }

    var isScalar: Bool {
        switch self {
        case .object, .list, .table: false
        default: true
        }
    }

    var scalar: String {
        switch self {
        case .string(let s): Self.quote(s)
        case .int(let i): "\(i)"
        case .double(let d): d == d.rounded() && abs(d) < 1e15 ? String(format: "%.1f", d) : "\(d)"
        case .bool(let b): b ? "true" : "false"
        case .null: "null"
        case .list(let items): "[" + items.map(\.scalar).joined(separator: ",") + "]"
        default: "…"
        }
    }

    /// Quotes when the bare text would be misread: empty, padded, delimiters, or looking like a number/bool/null.
    static func quote(_ s: String) -> String {
        let needs = s.isEmpty || s != s.trimmingCharacters(in: .whitespaces)
            || s.contains(where: { ",:\"\\\n\r\t[]{}".contains($0) }) || s.hasPrefix("-")
            || ["true", "false", "null"].contains(s) || Double(s) != nil
        guard needs else { return s }
        let escaped = s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\r", with: "\\r").replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }

    // MARK: JSON

    var json: Any {
        switch self {
        case .string(let s): s
        case .int(let i): i
        case .double(let d): d
        case .bool(let b): b
        case .null: NSNull()
        case .object(let pairs): Dictionary(pairs.map { ($0.0, $0.1.json) }, uniquingKeysWith: { a, _ in a })
        case .list(let items): items.map(\.json)
        case .table(let fields, let rows): rows.map { Dictionary(zip(fields, $0.map(\.json)), uniquingKeysWith: { a, _ in a }) }
        }
    }
}

/// Wraps an app reply value (JSON) as Out.
extension Out {
    init(any value: Any?) {
        switch value {
        case let s as String: self = .string(s)
        case let b as Bool: self = .bool(b)
        case let i as Int: self = .int(i)
        case let d as Double: self = .double(d)
        case let a as [Any]: self = .list(a.map { Out(any: $0) })
        case let o as [String: Any]: self = .object(o.keys.sorted().map { ($0, Out(any: o[$0])) })
        default: self = .null
        }
    }
}
