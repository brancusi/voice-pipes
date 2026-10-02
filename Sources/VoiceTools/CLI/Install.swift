import AppKit
import Foundation

extension VPCommands {
    /// `vp install`: links vp and voicepipes onto the PATH, without a password (/usr/local/bin when it's writable,
    /// otherwise ~/.local/bin). The app's Setup offers the /usr/local/bin version with a password.
    static func install(_ parsed: Parsed, _ out: Output) throws {
        let dir = parsed["dir"].map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) } ?? CLIInstaller.defaultDirectory
        let linked = try CLIInstaller.link(into: dir)
        let onPath = CLIInstaller.isOnPath(dir)
        out.emit(.object([
            ("linked", .list(linked.map { .string(ConfigPaths.tilde($0)) })),
            ("target", .string(ConfigPaths.tilde(CLIInstaller.executable))),
            ("on_path", .bool(onPath)),
        ]), help: onPath ? ["vp", "vp agents install   (the skill for Claude Code, Codex and others)"]
                         : ["echo 'export PATH=\"\(ConfigPaths.tilde(dir).replacingOccurrences(of: "~", with: "$HOME")):$PATH\"' >> ~/.zshrc", "vp agents install"])
    }

    static func agents(_ parsed: Parsed, _ out: Output) throws {
        switch parsed.positionals.first {
        case nil, "status":
            out.emit(.object([("skill", .table(["agent", "installed", "path"], AgentsInstaller.targets.map {
                [.string($0.name), .bool(AgentsInstaller.isInstalled($0)), .string(ConfigPaths.tilde($0.skillFile))]
            })), ("claude_session_hook", .bool(AgentsInstaller.hookInstalled))]), help: ["vp agents install [--hook]"])
        case "install":
            let installed = try AgentsInstaller.installSkill()
            var hook = AgentsInstaller.hookInstalled
            if parsed.has("hook") { try AgentsInstaller.installHook(); hook = true }
            out.emit(.object([("skill", .list(installed.map { .string(ConfigPaths.tilde($0)) })), ("claude_session_hook", .bool(hook))]),
                     help: installed.isEmpty ? ["mkdir -p ~/.claude/skills && vp agents install"] : hook ? [] : ["vp agents install --hook   (Claude Code: show Voice Pipes state at each session start)"])
        case "uninstall":
            let removed = AgentsInstaller.uninstall()
            out.emit(.object([("removed", .list(removed.map { .string(ConfigPaths.tilde($0)) }))]))
        case "context":
            // For the session hook: compact, never starts the app.
            let (config, issues) = loadConfig()
            let running = (try? AppClient.request("ping", launch: false)) != nil
            print("Voice Pipes (`vp`, \(binPath)): \(running ? "app running" : "app not running, starts on demand") · config \(issueSummary(issues)) · tracks: "
                  + (config?.tracks.map { $0.slug ?? $0.name }.joined(separator: ", ") ?? "none")
                  + ". Speak with `vp say \"…\"`, ask the user aloud with `vp ask \"…\"`, run a track with `vp run <id> --text \"…\"`; `vp help` for more.")
        default:
            throw UsageError("unknown_subcommand", "vp agents takes status, install, uninstall or context.", hint: "vp agents --help")
        }
    }
}

enum CLIInstaller {
    /// The app binary `vp` points at.
    static var executable: URL {
        (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).resolvingSymlinksInPath()
    }

    static var defaultDirectory: URL {
        let local = URL(fileURLWithPath: "/usr/local/bin")
        if FileManager.default.isWritableFile(atPath: local.path) { return local }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin")
    }

    static func link(into dir: URL) throws -> [URL] {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return try CLI.names.map { name in
            let link = dir.appendingPathComponent(name)
            if let existing = try? FileManager.default.destinationOfSymbolicLink(atPath: link.path) {
                guard existing != executable.path else { return link }
                try FileManager.default.removeItem(at: link)
            } else if FileManager.default.fileExists(atPath: link.path) {
                throw AppClient.Failure(code: "exists", message: "\(link.path) exists and isn't a Voice Pipes link; left alone.", hint: "vp install --dir <another dir>")
            }
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: executable)
            return link
        }
    }

    static func isOnPath(_ dir: URL) -> Bool {
        (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").contains { URL(fileURLWithPath: String($0)).standardizedFileURL == dir.standardizedFileURL }
    }

    /// Where `vp` currently resolves on the default PATHs, if linked to this app.
    static var installedLink: URL? {
        ["/usr/local/bin", "/opt/homebrew/bin", "\(NSHomeDirectory())/.local/bin"].map { URL(fileURLWithPath: $0).appendingPathComponent("vp") }
            .first { (try? FileManager.default.destinationOfSymbolicLink(atPath: $0.path)) != nil }
    }
}

/// The Agent Skill (and the opt-in Claude Code session hook), written into each agent's home that exists.
enum AgentsInstaller {
    struct Target {
        let name: String
        let home: URL
        var skillFile: URL { home.appendingPathComponent("skills/voice-pipes/SKILL.md") }
    }

    static var targets: [Target] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [Target(name: "claude-code", home: home.appendingPathComponent(".claude")),
                Target(name: "codex", home: home.appendingPathComponent(".codex")),
                Target(name: "agents", home: home.appendingPathComponent(".agents"))]
    }

    static func isInstalled(_ target: Target) -> Bool { FileManager.default.fileExists(atPath: target.skillFile.path) }

    /// Into every agent home that exists; ~/.claude when none do.
    @discardableResult
    static func installSkill() throws -> [URL] {
        var chosen = targets.filter { FileManager.default.fileExists(atPath: $0.home.path) }
        if chosen.isEmpty { chosen = [targets[0]] }
        for target in chosen {
            try FileManager.default.createDirectory(at: target.skillFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try skill.write(to: target.skillFile, atomically: true, encoding: .utf8)
        }
        return chosen.map(\.skillFile)
    }

    /// Keeps installed skills current after an update (the app calls this at launch).
    static func refreshIfInstalled() {
        for target in targets where isInstalled(target) {
            if (try? String(contentsOf: target.skillFile, encoding: .utf8)) != skill {
                try? skill.write(to: target.skillFile, atomically: true, encoding: .utf8)
            }
        }
    }

    static func uninstall() -> [URL] {
        var removed: [URL] = []
        for target in targets where isInstalled(target) {
            try? FileManager.default.removeItem(at: target.skillFile.deletingLastPathComponent())
            removed.append(target.skillFile)
        }
        if hookInstalled, (try? removeHook()) != nil { removed.append(claudeSettings) }
        return removed
    }

    // MARK: Claude Code session hook

    static var claudeSettings: URL { targets[0].home.appendingPathComponent("settings.json") }
    private static var hookCommand: String { "\(CLIInstaller.installedLink?.path ?? CLIInstaller.executable.path) agents context" }

    static var hookInstalled: Bool {
        ((try? String(contentsOf: claudeSettings, encoding: .utf8)) ?? "").contains("agents context")
    }

    /// Adds a SessionStart hook that prints `vp agents context`, keeping everything else in settings.json (backed up).
    static func installHook() throws {
        guard !hookInstalled else { return }
        var settings = (try? JSONSerialization.jsonObject(with: Data(contentsOf: claudeSettings))) as? [String: Any] ?? [:]
        if let data = try? Data(contentsOf: claudeSettings) { try data.write(to: claudeSettings.appendingPathExtension("voice-pipes-backup")) }
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        var start = hooks["SessionStart"] as? [[String: Any]] ?? []
        start.append(["hooks": [["type": "command", "command": hookCommand]]])
        hooks["SessionStart"] = start
        settings["hooks"] = hooks
        try FileManager.default.createDirectory(at: claudeSettings.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]).write(to: claudeSettings)
    }

    static func removeHook() throws {
        guard var settings = (try? JSONSerialization.jsonObject(with: Data(contentsOf: claudeSettings))) as? [String: Any],
              var hooks = settings["hooks"] as? [String: Any], var start = hooks["SessionStart"] as? [[String: Any]] else { return }
        start.removeAll { entry in ((entry["hooks"] as? [[String: Any]]) ?? []).contains { ($0["command"] as? String)?.hasSuffix("agents context") == true } }
        hooks["SessionStart"] = start.isEmpty ? nil : start
        settings["hooks"] = hooks.isEmpty ? nil : hooks
        try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]).write(to: claudeSettings)
    }

    // MARK: The skill

    static let skill = """
        ---
        name: voice-pipes
        description: Use the user's Voice Pipes app through the `vp` CLI. Speak to the user aloud (`vp say`), ask them a question by voice and get their spoken answer (`vp ask`), record and transcribe them (`vp listen`) or an audio file (`vp transcribe`), run their voice pipelines ("tracks") with text in (`vp run <id> --text`), and read or change their tracks, hotkeys, vocabulary and keys (config.toml, `vp config`, `vp vocab`, `vp auth`). Use when the user mentions Voice Pipes, tracks, dictation, reading aloud, voice notes, or wants to be told or asked something out loud.
        ---

        # Voice Pipes (`vp`)

        Voice Pipes is a Mac menu bar app: hotkey-triggered pipelines ("tracks") of blocks. Audio or text goes in,
        runs through blocks (transcribe on the Mac, fix words, an LLM, Jev routing, HTTP, templates), and comes out
        pasted, spoken, or sent somewhere. `vp` is its CLI. Run `vp` alone first: it prints live state and the tracks.

        Output is TOON (add `--json` for JSON). Errors print on stdout as `error:` with `code`, `message`, `hint`;
        exit 0 = ok, 1 = error, 2 = bad usage. Follow the `help[]` lines at the end of each output. Nothing prompts.
        Commands that need the app start it in the background.

        ## Talk to the user

        - `vp say "Tests passed; 3 files changed."` speaks and waits until done. `--voice <id>` (`vp voices`),
          `--model pocket|supertonic|macos|<openrouter-id>`, `--speed 0.6–2.0`. Pipe long text: `… | vp say`.
        - `vp ask "Deploy to staging or production?"` speaks the question, records the user's reply until they stop
          talking, and prints `answer:`. Use it when you need a decision and the user may not be at the screen.
          `--max 30` caps the recording; `--silence 1.2` is how long a pause ends it.
        - `vp listen` records and transcribes without speaking first. `vp stop` stops speech or recording.
        - Keep spoken text short and plain: no markdown, code or URLs; they are read out literally.

        ## Run the user's pipelines

        - `vp tracks` lists them (`id`, name, hotkeys); `vp tracks show <id>` shows the blocks.
        - `vp run <id> --text "…"` starts at the track's first block that takes text and prints the final text
          (e.g. a cleanup track returns cleaned text; a notes track posts to its endpoint). A track that ends in
          paste pastes at the user's cursor, so prefer tracks without paste unless the user asked.
        - `vp transcribe recording.m4a` transcribes a file on the Mac (Parakeet, fast, private).
        - `vp history --limit 5` shows recent runs (what was said, what came out, timings); `vp history show <n>`.
        - `vp watch` streams run events as they happen.

        ## Change the configuration

        Everything lives in `~/.config/voice-pipes/config.toml` (tracks, hotkeys, settings) and `vocabulary.toml`
        beside it. Both have JSON Schemas beside them and a full reference at the end of config.toml
        (`vp help config` prints it).

        1. Read the file; keep its layout. Each track is `[[track]]` with `id`, `name`, `color`, `enabled`,
           `hotkeys = [{ keys = "option+space", mode = "hold" }]`, then `[[track.step]]` blocks with `type = …`.
        2. Edit it, then run `vp config check`. It reports errors with line and path and "did you mean" hints.
        3. The app reloads within a second. A file that doesn't check out is not applied (the last good version
           keeps running), so always check. `vp config backups` / `vp config restore <n>` undo.
        - Never put API keys or tokens in the file. Use `vp secret set <name>` (pipe the value in) and reference
          `${secret:<name>}` in an http block's url, headers or body.
        - Ask the user before changing or removing their hotkeys or tracks; adding a new track is fine.
        - Vocabulary: `vp vocab add "Kubernetes" --heard "cuban eighties, cube or netties"`; `vp vocab test "…"`.

        ## Keys and status

        - `vp status` shows permissions, on-device models, keys (masked) and problems.
        - `vp auth login openrouter` signs in through the browser (needs the user); `--headless` then
          `--code <code>` on a machine without a browser. `echo "$KEY" | vp auth set typesafe` for Jev.
        - Never print, echo or log key values.

        ## Example: a voice-notes track

        ```toml
        [[track]]
        id = "voice-note"
        name = "Voice note"
        color = "marigold"
        hotkeys = [{ keys = "option+n", mode = "toggle" }]

          [[track.step]]
          type = "microphone"

          [[track.step]]
          type = "transcribe"
          model = "parakeet"

          [[track.step]]
          type = "fix-words"

          [[track.step]]
          type = "http"
          method = "POST"
          url = "https://api.example.com/notes"
          headers = { Authorization = "Bearer ${secret:notes}", "Content-Type" = "application/json" }
          body = '{"text": {{input_json}}}'
          response_field = ""
        ```

        Then `vp config check`, and `vp run voice-note --text "remember to renew the cert"` to try it.
        """
}
