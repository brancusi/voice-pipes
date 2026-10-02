import Foundation
import TOMLDecoder

/// vocabulary.toml ⇄ the Fix words list.
enum VocabularyFile {
    struct Result {
        var entries: [VocabularyEntry]?
        var errors: [ConfigIssue]
        var warnings: [ConfigIssue]
    }

    static func parse(_ text: String) -> Result {
        let root: [String: TOMLValue]
        do {
            guard case .table(let t) = try TOMLDecoder().decode(TOMLValue.self, from: text) else {
                return Result(entries: nil, errors: [ConfigIssue(severity: .error, path: "", message: "isn't a TOML table")], warnings: [])
            }
            root = t
        } catch {
            return Result(entries: nil, errors: [ConfigFile.syntaxIssue(error)], warnings: [])
        }
        var top = TableReader(root, path: "")
        _ = top.int("version")
        var entries: [VocabularyEntry] = []
        var seen = Set<String>()
        for (index, table) in (top.tables("word") ?? []).enumerated() {
            var r = TableReader(table, path: "word[\(index + 1)]")
            let write = r.string("write", required: true) ?? ""
            if write.trimmingCharacters(in: .whitespaces).isEmpty { r.error("write", "is empty") }
            if seen.contains(write.lowercased()) { r.warning("write", "'\(write)' is listed twice; both apply") }
            seen.insert(write.lowercased())
            let heard = r.strings("heard_as") ?? []
            entries.append(VocabularyEntry(write: write, heardAs: heard, alwaysExact: r.bool("always_exact") ?? false))
            r.finish(known: ["write", "heard_as", "always_exact"])
            top.issues += r.issues
        }
        top.finish(known: ["version", "word"])
        let errors = top.issues.filter { $0.severity == .error }
        return Result(entries: errors.isEmpty ? entries : nil, errors: errors, warnings: top.issues.filter { $0.severity == .warning })
    }

    static func write(_ entries: [VocabularyEntry]) -> String {
        var out = header + "version = 1\n"
        for entry in entries where !entry.write.trimmingCharacters(in: .whitespaces).isEmpty {
            out += "\n[[word]]\n"
            out += "write = \(ConfigFile.quote(entry.write))\n"
            out += "heard_as = [" + entry.heardAs.map(ConfigFile.quote).joined(separator: ", ") + "]\n"
            if entry.alwaysExact { out += "always_exact = true\n" }
        }
        return out
    }

    static let header = """
        #:schema ./vocabulary.schema.json
        # ════════════════════════════════════════════════════════════════════════════════════════════════════
        #  voice | pipes · vocabulary.toml
        # ════════════════════════════════════════════════════════════════════════════════════════════════════
        #
        #  Words transcription keeps getting wrong. Every Fix words block replaces each `heard_as` phrase with
        #  `write`, on this Mac, instantly: whole words only, any capitalisation. LLM blocks get the list as a
        #  glossary too.
        #
        #    write         the spelling you want, e.g. "Claude Code"
        #    heard_as      what transcription writes instead; list only phrases you never mean literally
        #    always_exact  true keeps an all-lowercase spelling lowercase even at the start of a sentence
        #                  (spellings with capitals are always written exactly)
        #
        #  Saves reload within a second.  vp vocab  lists,  vp vocab add "Kubernetes" --heard "cuban eighties",
        #  vp vocab test "some sentence" shows the result,  vp vocab train "<word>" opens training in the app.
        # ════════════════════════════════════════════════════════════════════════════════════════════════════


        """
}
