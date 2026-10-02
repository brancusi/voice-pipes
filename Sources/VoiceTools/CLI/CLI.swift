import AppKit
import Foundation

/// `vp` (also `voicepipes`): the app's own binary, run under that name. Agent-first (axi.md): TOON output (--json
/// for JSON), a live home view, help[] next steps, structured errors on stdout, exit 0 ok · 1 error · 2 usage,
/// no prompts. File commands work without the app; the rest start it in the background.
enum CLI {
    static let names = ["vp", "voicepipes"]
    static let description = "Voice Pipes from the command line: run tracks (hotkey voice pipelines), speak, listen, transcribe, and manage their config, vocabulary, keys and history."

    static var isInvocation: Bool {
        let args = CommandLine.arguments
        return names.contains(URL(fileURLWithPath: args[0]).lastPathComponent) || args.dropFirst().first == "--cli"
    }

    static func main() -> Never {
        var args = Array(CommandLine.arguments.dropFirst())
        if args.first == "--cli" { args.removeFirst() }
        let json = args.contains("--json")
        let full = args.contains("--full")
        args.removeAll { $0 == "--json" || $0 == "--full" }
        let output = Output(json: json, full: full)
        do {
            try run(args, output)
            exit(0)
        } catch let usage as UsageError {
            output.error(code: usage.code, message: usage.message, hint: usage.hint)
            exit(2)
        } catch let failure as AppClient.Failure {
            output.error(code: failure.code, message: failure.message, hint: failure.hint)
            exit(1)
        } catch {
            output.error(code: "failed", message: error.localizedDescription, hint: nil)
            exit(1)
        }
    }

    // MARK: Dispatch

    static func run(_ args: [String], _ out: Output) throws {
        guard let command = args.first else { return try VPCommands.home(out) }
        if command == "--help" || command == "-h" || command == "help" { return VPCommands.help(Array(args.dropFirst()), out) }
        if command == "--version" || command == "version" {
            return out.emit(.object([("version", .string(VPCommands.version))]))
        }
        guard let spec = VPCommands.table.first(where: { $0.name == command }) else {
            throw UsageError("unknown_command", "No command '\(command)'.\(TableReader.suggestion(command, VPCommands.table.map(\.name)))", hint: "vp help")
        }
        let parsed = try Parsed(Array(args.dropFirst()), spec: spec)
        if parsed.flags["help"] != nil { return VPCommands.help([command], out) }
        try spec.handler(parsed, out)
    }
}

struct UsageError: Error {
    let code: String
    let message: String
    let hint: String?
    init(_ code: String, _ message: String, hint: String? = nil) {
        self.code = code
        self.message = message
        self.hint = hint
    }
}

/// A command: its name, the flags it takes (value flags and switches), a one-line summary and usage, and what it does.
struct CommandSpec {
    let name: String
    let usage: String
    let summary: String
    var values: [String] = []
    var switches: [String] = []
    let handler: (Parsed, Output) throws -> Void
}

/// Positionals and flags, checked against the command's spec: an unknown flag fails loud (exit 2).
struct Parsed {
    var positionals: [String] = []
    var flags: [String: String] = [:]

    init(_ args: [String], spec: CommandSpec) throws {
        var i = 0
        while i < args.count {
            let arg = args[i]
            if arg.hasPrefix("--"), arg.count > 2 {
                var name = String(arg.dropFirst(2))
                var value: String?
                if let eq = name.firstIndex(of: "=") {
                    value = String(name[name.index(after: eq)...])
                    name = String(name[..<eq])
                }
                if name == "help" {
                    flags["help"] = "true"
                } else if spec.switches.contains(name) {
                    flags[name] = value ?? "true"
                } else if spec.values.contains(name) {
                    if value == nil {
                        i += 1
                        guard i < args.count else { throw UsageError("missing_value", "--\(name) needs a value.", hint: "vp \(spec.name) --help") }
                        value = args[i]
                    }
                    flags[name] = value
                } else {
                    throw UsageError("unknown_flag", "vp \(spec.name) has no --\(name).\(TableReader.suggestion(name, spec.values + spec.switches))",
                                     hint: "vp \(spec.name) --help")
                }
            } else {
                positionals.append(arg)
            }
            i += 1
        }
    }

    subscript(_ flag: String) -> String? { flags[flag] }
    func has(_ flag: String) -> Bool { flags[flag] != nil }

    func double(_ flag: String) throws -> Double? {
        guard let raw = flags[flag] else { return nil }
        guard let value = Double(raw) else { throw UsageError("bad_value", "--\(flag) should be a number, not '\(raw)'.") }
        return value
    }

    func int(_ flag: String) throws -> Int? {
        guard let raw = flags[flag] else { return nil }
        guard let value = Int(raw) else { throw UsageError("bad_value", "--\(flag) should be a whole number, not '\(raw)'.") }
        return value
    }

    func positional(_ index: Int, _ name: String, usage: String) throws -> String {
        guard index < positionals.count else { throw UsageError("missing_argument", "Missing <\(name)>.", hint: usage) }
        return positionals[index]
    }
}

/// Prints TOON (default) or JSON, with help[] next steps; errors go to stdout too, so agents see them.
struct Output {
    let json: Bool
    let full: Bool

    func emit(_ doc: Out, help: [String] = []) {
        if json {
            let data = (try? JSONSerialization.data(withJSONObject: doc.json, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
            print(String(data: data, encoding: .utf8) ?? "{}")
            return
        }
        var text = doc.toon()
        if !help.isEmpty { text += "\nhelp[\(help.count)]:\n" + help.map { "  " + Self.helpLine($0) }.joined(separator: "\n") }
        print(text)
    }

    /// "vp a   ·   vp b   (note)" → "Run `vp a` or `vp b` (note)"; plain prose (no leading command) stays as is.
    static func helpLine(_ line: String) -> String {
        var commands = line
        var note = ""
        if let range = line.range(of: "   (") {
            commands = String(line[..<range.lowerBound])
            note = " " + line[range.upperBound...].trimmingCharacters(in: .whitespaces).dropFirst(0)
            note = " (" + note.dropFirst()
        }
        let parts = commands.components(separatedBy: "   ·   ").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.allSatisfy({ $0.hasPrefix("vp") || $0.hasPrefix("echo") || $0.hasPrefix("open ") || $0.hasPrefix("mkdir") }) else {
            return line
        }
        return "Run " + parts.map { "`\($0)`" }.joined(separator: " or ") + note
    }

    func error(code: String, message: String, hint: String?) {
        var pairs: [(String, Out)] = [("code", .string(code)), ("message", .string(message))]
        if let hint { pairs.append(("hint", .string(hint))) }
        emit(.object([("error", .object(pairs))]))
    }

    /// Long text cut to `limit` with a size hint, unless --full.
    func trim(_ text: String, _ limit: Int = 160) -> String {
        guard !full, text.count > limit else { return text }
        return String(text.prefix(limit)) + "… (truncated, \(text.count) chars total; use --full)"
    }
}

/// Text from the arguments, or piped in on stdin (never a prompt).
func textArgument(_ parsed: Parsed, from index: Int, flag: String = "text") -> String? {
    if let text = parsed[flag] { return text == "-" ? readStdin() : text }
    let rest = parsed.positionals.dropFirst(index)
    if rest.first == "-" { return readStdin() }
    if !rest.isEmpty { return rest.joined(separator: " ") }
    // Piped text (`echo … | vp say`). Only if it's there within 200 ms: an agent's shell may leave stdin as an open,
    // empty pipe, and waiting on it would hang.
    if isatty(STDIN_FILENO) == 0 {
        var fds = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
        if poll(&fds, 1, 200) > 0, fds.revents & Int16(POLLIN) != 0 { return readStdin() }
    }
    return nil
}

private func readStdin() -> String? {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    return text?.isEmpty == false ? text : nil
}
