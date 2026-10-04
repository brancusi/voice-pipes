import AppKit
import SwiftUI
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
            let agents = config?.agents ?? AgentSettings()
            print("Voice Pipes (`vp`, \(binPath)): \(running ? "app running" : "app not running, starts on demand") · config \(issueSummary(issues)) · tracks: "
                  + (config?.tracks.map { $0.slug ?? $0.name }.joined(separator: ", ") ?? "none")
                  + ". Read aloud without being asked: \(agents.readAloud.rawValue) (\(agents.readAloud.meaning); long = over \(agents.longText) characters)."
                  + " Speak with `vp say \"…\"` (long text: `vp open reading` first), ask aloud with `vp ask \"…\"`, run a track with `vp run <id> --text \"…\"`; the voice-pipes skill has the rest.")
        case "read-aloud":
            // What agents read aloud unasked: [settings.agents] in config.toml (the app picks it up within a second).
            let (loaded, issues) = loadConfig()
            guard var config = loaded else {
                throw AppClient.Failure(code: "config_invalid", message: "config.toml doesn't check out: \(issues.first?.description ?? "")", hint: "vp config check")
            }
            if let mode = parsed.positionals.dropFirst().first {
                guard let value = AgentSettings.ReadAloud(rawValue: mode) else {
                    throw UsageError("bad_value", "read-aloud is off, long, attention or all.\(TableReader.suggestion(mode, AgentSettings.ReadAloud.allCases.map(\.rawValue)))")
                }
                config.agents.readAloud = value
            }
            if let chars = try parsed.int("long-text") { config.agents.longText = max(50, chars) }
            if config.agents != (loaded?.agents ?? config.agents) || parsed.positionals.count > 1 || parsed["long-text"] != nil { try writeConfig(config) }
            out.emit(.object([("read_aloud", .string(config.agents.readAloud.rawValue)), ("means", .string(config.agents.readAloud.meaning)),
                              ("long_text", .int(config.agents.longText))]),
                     help: ["vp agents read-aloud off|long|attention|all [--long-text <chars>]"])
        default:
            throw UsageError("unknown_subcommand", "vp agents takes status, install, uninstall, context or read-aloud.", hint: "vp agents --help")
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
            if (try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) != nil {
                guard isVoicePipes(link) || !FileManager.default.fileExists(atPath: link.path) else {
                    throw AppClient.Failure(code: "exists", message: "\(link.path) points at another program; left alone.", hint: "vp install --dir <another dir>")
                }
                if link.resolvingSymlinksInPath() == executable { return link }
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

    /// Where `vp` currently resolves on the default PATHs, if linked to this app (any copy of it).
    static var installedLink: URL? {
        ["/usr/local/bin", "/opt/homebrew/bin", "\(NSHomeDirectory())/.local/bin"].map { URL(fileURLWithPath: $0).appendingPathComponent("vp") }
            .first { (try? FileManager.default.destinationOfSymbolicLink(atPath: $0.path)) != nil && isVoicePipes($0) }
    }

    /// True when `url` resolves to the executable inside a Voice Pipes app bundle.
    static func isVoicePipes(_ url: URL) -> Bool {
        let exe = url.resolvingSymlinksInPath()
        let app = exe.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return app.pathExtension == "app" && Bundle(url: app)?.bundleIdentifier == "io.github.brancusi.voice-tools"
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
    /// At launch: rewrite installed skills that are out of date, and give the skill to agents installed since (an
    /// agent home that appeared, e.g. ~/.codex). Nothing happens if the skill isn't installed anywhere
    /// (`vp agents uninstall` sticks).
    static func refreshIfInstalled() {
        guard targets.contains(where: isInstalled) else { return }
        for target in targets where isInstalled(target) || FileManager.default.fileExists(atPath: target.home.path) {
            if (try? String(contentsOf: target.skillFile, encoding: .utf8)) != skill {
                try? FileManager.default.createDirectory(at: target.skillFile.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? skill.write(to: target.skillFile, atomically: true, encoding: .utf8)
            }
        }
        refreshHook()
    }

    /// The session hook names vp's path; after the app moved (or vp was linked since), point it at the current one.
    private static func refreshHook() {
        guard hookInstalled, var settings = try? readSettings(), var hooks = settings["hooks"] as? [String: Any],
              var start = hooks["SessionStart"] as? [[String: Any]] else { return }
        var changed = false
        for i in start.indices {
            guard var entries = start[i]["hooks"] as? [[String: Any]] else { continue }
            for j in entries.indices {
                if let command = entries[j]["command"] as? String, command.hasSuffix("agents context"), command != hookCommand {
                    entries[j]["command"] = hookCommand
                    changed = true
                }
            }
            start[i]["hooks"] = entries
        }
        guard changed else { return }
        hooks["SessionStart"] = start
        settings["hooks"] = hooks
        try? writeSettings(settings)
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
    /// Quoted for the shell (the app's path has a space); the bundle executable needs `--cli` to act as `vp`.
    private static var hookCommand: String {
        let quote = { (path: String) in "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        if let link = CLIInstaller.installedLink { return "\(quote(link.path)) agents context" }
        return "\(quote(CLIInstaller.executable.path)) --cli agents context"
    }

    static var hookInstalled: Bool {
        ((try? String(contentsOf: claudeSettings, encoding: .utf8)) ?? "").contains("agents context")
    }

    /// settings.json as an object; nil when there's none yet. Anything else is left alone.
    private static func readSettings() throws -> [String: Any]? {
        guard let data = try? Data(contentsOf: claudeSettings) else { return nil }
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) { return [:] }
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw AppClient.Failure(code: "claude_settings_invalid", message: "~/.claude/settings.json isn't a JSON object, so it was left alone.",
                                    hint: "fix it, then vp agents install --hook")
        }
        return object
    }

    /// Keeps a dated copy of the old file, then replaces it atomically (through a symlink, if it is one).
    private static func writeSettings(_ settings: [String: Any]) throws {
        let target = claudeSettings.resolvingSymlinksInPath()
        if let data = try? Data(contentsOf: target) {
            let stamp = ISO8601DateFormatter.backup.string(from: Date())
            try data.write(to: target.deletingLastPathComponent().appendingPathComponent("settings.json.voice-pipes-\(stamp).bak"))
        }
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            .write(to: target, options: .atomic)
    }

    /// Adds a SessionStart hook that prints `vp agents context`, keeping everything else in settings.json (backed up).
    static func installHook() throws {
        guard !hookInstalled else { return }
        var settings = try readSettings() ?? [:]
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        var start = hooks["SessionStart"] as? [[String: Any]] ?? []
        start.append(["hooks": [["type": "command", "command": hookCommand]]])
        hooks["SessionStart"] = start
        settings["hooks"] = hooks
        try writeSettings(settings)
    }

    static func removeHook() throws {
        guard var settings = try readSettings(),
              var hooks = settings["hooks"] as? [String: Any], var start = hooks["SessionStart"] as? [[String: Any]] else { return }
        start.removeAll { entry in ((entry["hooks"] as? [[String: Any]]) ?? []).contains { ($0["command"] as? String)?.hasSuffix("agents context") == true } }
        hooks["SessionStart"] = start.isEmpty ? nil : start
        settings["hooks"] = hooks.isEmpty ? nil : hooks
        try writeSettings(settings)
    }

    // MARK: The skill

    /// The skill: the guide, then the block and settings reference generated from config.toml's own, so the two
    /// never disagree.
    static var skill: String { skillGuide + "\n## Reference: every block and setting (the same as config.toml's)\n\n```\n" + referenceText + "```\n" }

    /// config.toml's reference without its comment marks and rules.
    private static var referenceText: String {
        ConfigFile.reference.split(separator: "\n", omittingEmptySubsequences: false).compactMap { line -> String? in
            let text = line.hasPrefix("# ") ? String(line.dropFirst(2)) : line == "#" ? "" : String(line)
            if text.contains("════") || text.trimmingCharacters(in: .whitespaces) == "Reference" { return nil }
            return text.hasPrefix(" ") ? String(text.dropFirst()) : text
        }.joined(separator: "\n").trimmingCharacters(in: .newlines) + "\n"
    }

    private static let skillGuide = """
        ---
        name: voice-pipes
        description: Use the user's Voice Pipes app through the `vp` CLI and its config file. Build a new voice pipeline ("track") or change one from a plain-language request (blocks such as transcribe, LLM, Jev branch/route, HTTP, speak, paste, edited in ~/.config/voice-pipes/config.toml and checked with `vp config check`); run tracks with text (`vp run <id> --text`); speak to the user (`vp say`), ask them aloud and get the spoken answer (`vp ask`), transcribe (`vp listen`, `vp transcribe`); and read long text aloud in a HUD they can follow and steer. Follow the user's read-aloud preference (`vp agents read-aloud`): it may ask you to read summaries or anything needing their attention out loud. Use when the user mentions Voice Pipes, tracks, pipelines, hotkeys, dictation, vocabulary, reading aloud, voice notes, says "read this to me", or wants to hear or be asked something.
        ---

        # Voice Pipes (`vp`)

        Voice Pipes is a Mac menu bar app: hotkey-triggered pipelines ("tracks") of blocks. Audio or text goes in,
        runs through blocks (transcribe on the Mac, fix words, an LLM, Jev routing, HTTP, templates), and comes out
        pasted, spoken, or sent somewhere. `vp` is its CLI. Run `vp` alone first: it prints live state and the tracks.

        Output is TOON (add `--json` for JSON). Errors print on stdout as `error:` with `code`, `message`, `hint`;
        exit 0 = ok, 1 = error, 2 = bad usage. Follow the `help[]` lines at the end of each output. Nothing prompts.
        Commands that need the app start it in the background.

        At the start of a session: run `vp` (state and tracks) and `vp agents read-aloud` (the user's standing
        preference for what you read aloud, below). Follow that preference for the whole session. The session
        context line, if the hook is installed, already states it.

        ## Talk to the user

        - `vp say "Tests passed; 3 files changed."` speaks and waits until done. `--voice <id>` (`vp voices`),
          `--model pocket|supertonic|macos|<openrouter-id>`, `--speed 0.6–2.0`. Pipe long text: `… | vp say`.
        - `vp ask "Deploy to staging or production?"` speaks the question, records the user's reply until they stop
          talking, and prints `answer:`. Use it when you need a decision and the user may not be at the screen.
          `--max 30` caps the recording; `--silence 1.2` is how long a pause ends it.
        - `vp listen` records and transcribes without speaking first. `vp stop` stops speech or recording.
        - `vp speed 1.4` changes the speed of what's playing.

        ## Read aloud: the user's standing preference

        `vp agents read-aloud` prints it (`read_aloud` in config.toml `[settings.agents]`). It applies to your own
        replies, in every session, without the user asking again:

        | mode | read aloud |
        |---|---|
        | `off` | only when the user asks ("read this to me") |
        | `long` | long, rich text: a summary, report, plan, explanation or review longer than `long_text` characters (default 600). Not short answers, not code, diffs or logs |
        | `attention` | everything `long` reads, plus anything that needs the user: a question or decision you're waiting on, a finished task, a failure or blocker (a sentence or two: what happened and what you need) |
        | `all` | every reply, as a short spoken version |

        - The user says "read me anything that needs my attention" or "stop reading things to me": set it with
          `vp agents read-aloud attention` (or `off`, `long`, `all`), so every agent and later session follows it.
        - Read a spoken version, not the raw reply: what matters, in plain sentences. Leave code, file paths, diffs,
          tables and URLs on screen and say they're there ("the diff is in the chat").
        - Long readings: `vp open reading` first, then `printf '%s' "$TEXT" | vp say`. Short heads-ups: just `vp say`.
        - One reading at a time; wait for `vp say` to return before starting another or asking anything aloud.
        - Still write the full reply as text too; reading is in addition, never instead.

        ## Change how Voice Pipes reads to the user (when they ask)

        These are the user's preferences; change them only when they ask, then confirm in a sentence:
        - What agents read aloud unasked (default `attention`): "only read me long stuff" → `vp agents read-aloud
          long`; "stop reading things to me" → `off`; "read me everything" → `all`; "read me what needs my
          attention" → `attention`. `--long-text <chars>` sets what counts as long.
        - When the HUD takes the keyboard during a reading (default `always`; their app stays in front): "don't take
          my keys" → `vp reading keys hover` (when they point at or click it) or `click` or `never`; "always take
          them" → `vp reading keys always`. `vp reading click-away stop|keep-reading`.
        - Which keys do what: `vp reading key faster period shift+equal` (actions: stop, pause, next, previous,
          slower, faster, start, end); shortcuts that work in any app while reading: `vp reading shortcut faster
          control+option+right` (needs a modifier; `none` removes it). `vp reading` shows them all; `vp reading
          reset` restores the defaults (Esc, Space, j/k, h/l, g/G).

        ## Read long text to the user

        Voice Pipes can read a long summary, report or answer aloud while the user sits back and listens. The HUD
        at the bottom of their screen shows the text with the sentence being read lit up and a cursor under the
        word, and they steer it themselves: click any sentence to jump there, − / + for speed, pause, stop.

        When the user says "read this to me", "read me the summary", or wants to listen instead of read:
        1. Write it for listening: plain spoken sentences and short paragraphs. No markdown, bullets, tables, code,
           file paths or URLs (they're read out literally); say "three things" and then the three things.
        2. `vp open reading` (shows the follow-along card), then pipe the text in: `printf '%s' "$TEXT" | vp say`.
           `vp say` returns when the reading ends, whether it finished, was stopped or the user jumped around.
        3. Don't talk over it: wait for `vp say` to return before speaking or asking anything else.
        - The user controls it from the HUD (and its keys: by default Esc stops, Space pauses, j/k move by sentence,
          h/l change speed; they set when the HUD takes the keyboard in Setup → Reading). You can too:
          `vp next`, `vp prev`, `vp speed <0.6–2.0>`, `vp pause`, `vp resume`, `vp stop`.
        - `vp close reading` hides the card for later readings (the user's choice is remembered either way).
        - Keep spoken text short and plain: no markdown, code or URLs; they are read out literally.

        ## Run the user's pipelines

        - `vp tracks` lists them (`id`, name, hotkeys); `vp tracks show <id>` shows the blocks.
        - `vp run <id> --text "…"` starts at the track's first block that takes text and prints the final text
          (e.g. a cleanup track returns cleaned text; a notes track posts to its endpoint). A track that ends in
          paste pastes at the user's cursor, so prefer tracks without paste unless the user asked.
        - `vp transcribe recording.m4a` transcribes a file on the Mac (Parakeet, fast, private).
        - `vp history --limit 5` shows recent runs (what was said, what came out, timings); `vp history show <n>`.
        - `vp watch` streams run events as they happen.

        ## Build or change a pipeline for the user

        The user describes what they want in plain language; you turn it into blocks in
        `~/.config/voice-pipes/config.toml`. The file IS the app's configuration, one-to-one: every track, block,
        branch, hotkey and setting the app's editor shows is in it, and the app reloads it within a second. Never ask
        the user to click through the app to build something. `vocabulary.toml` beside it holds the word fixes.

        1. Understand the job: what goes in (their voice, selected text, the clipboard), what should happen to it,
           where it goes (pasted, copied, spoken, posted to a service), and the hotkey (hold or toggle).
        2. Look at what exists: `vp tracks`, `vp tracks show <id>` (blocks numbered; branches as 2.easy, 2.hard.1),
           and the file itself. Changing a track: read its `[[track]]` table and edit only what was asked.
        3. Write the blocks (the reference below lists every block and setting). Keep the file's layout and comments;
           give a new track a unique `id` (lowercase, dashes) and a hotkey nothing else uses (`vp tracks` shows the
           used ones; option+letter or control+option+letter are usually free).
        4. `vp config check`. Errors come with line, path and "did you mean"; fix and check again. A file that
           doesn't check out is not applied (the last good version keeps running).
        5. Show it: `vp open track <id>` (each save flashes what changed in the open editor), optionally
           `--step <n>` to open a block.
        6. Try it: `vp run <id> --text "sample"` prints the result; `vp history show 1` shows how it ran, step by
           step, with Jev's pick and the tokens and cost. Careful: a track ending in `paste` pastes at the user's
           cursor and one with `speak` talks; for a quiet test, say so or test a copy without those blocks.
        7. Tell the user what you built in a sentence or two (and its hotkey), or read it aloud per their preference.

        Choosing blocks:
        - Voice in: `microphone` then `transcribe` (`model = "parakeet"` on this Mac, fast and private; or an
          OpenRouter id for cloud accuracy), usually `fix-words` next (their vocabulary).
        - Text in: `text` with `sources` (selection, page, clipboard; first with text wins).
        - Change the text: `llm` (any OpenRouter model, `vp models --capability text --search <name>`; `{{input}}` in
          the prompt places the text; `on_failure = "pass-through"` keeps a track working offline), `template`, `http`.
        - Out: `paste`, `copy`, `speak` (`vp voices --model pocket`), `show-hud`, or `http` to post somewhere.
          Outputs pass their text on, so a track can paste and then post.
        - Different handling for different input: `branch`. Jev answers your `question` about the text and picks a
          branch by its `when`; that branch's own steps run, then the track continues. Use it for how hard or long the
          text is, what it's about, its language, or whether it's a question or a note. A branch with no steps
          passes the text through. Give every branch a distinct, concrete `when` (Jev chooses by it).
        - Just choosing which model answers: `route` (each route = name, when, model, prompt); simpler than a branch
          when every path is one LLM call.
        - Rules the check enforces: inputs (`microphone`, `text`) only start a track; branches start from text;
          each block takes what the previous one gives; if branches end differently (one speaks, one gives text),
          nothing can follow the branch, so put the remaining steps inside each branch.
        - Secrets for http blocks: `vp secret set <name>` (pipe the value), then `${secret:<name>}`. Never put keys in
          the file. Provider keys: `vp auth`.
        - Ask before changing or removing the user's existing hotkeys or tracks; adding a new track is fine.
          `vp config backups` / `vp config restore <n>` undo.
        - Vocabulary: `vp vocab add "Kubernetes" --heard "cuban eighties, cube or netties"`; `vp vocab test "…"`.

        ## Show the user (no screen access needed)

        The app's windows are driven from `vp`; you never need screenshots or clicks. Each of these answers with
        what's on screen (`vp ui` alone prints it), and whatever it points at flashes rose for a moment.

        - `vp open track <id>` opens a track in the editor; `--step <n>` opens that block's settings, `--route <n>`
          a Route block's route card, `--field <name>` puts the cursor in a field (`name`; a block's `prompt`,
          `url`, `headers`, `body`, `response_field`, `template`; a route's `name`, `when`, `prompt`).
          `--section title|triggers|pipeline` scrolls to a part.
        - `vp open history [--track <id>] [--search "…"] [--run <n>]`, `vp open vocabulary [--word "…"] [--add]`,
          `vp open setup [--section checks|connections|cli|models|microphone|appearance|reading|updates] [--field openrouter-key]`,
          `vp open onboarding [--step welcome|permissions|models|keys|agents|try]`, `vp open menu` (the menu bar
          panel), `vp open about`.
        - `--background` shows a window without taking the keyboard from the user's current app.
        - `vp close main|menu|about|onboarding|sheet|all`.
        - Building a track for the user: `vp open track <id>` first, then edit config.toml. Each save flashes what
          changed in the open editor and opens a single new or changed block, so they watch it take shape. Finish
          with `vp run <id> --text "…"` to demo it, or `vp say` to explain it.

        ## Install, reinstall, remove

        If `vp` isn't found, install everything (app, `vp`, this skill) without prompts:
        `curl -fsSL https://github.com/brancusi/voice-tools-releases/releases/latest/download/install.sh | bash`. Add `-s -- --no-launch`, `--version <x.y.z>` or `--uninstall` as needed. The user must still
        grant Microphone and Accessibility in the app's first-run window.

        ## Keys and status

        - `vp status` shows permissions, on-device models, keys (masked) and problems.
        - `vp auth login openrouter` signs in through the browser (needs the user); `--headless` then
          `--code <code>` on a machine without a browser. `echo "$KEY" | vp auth set typesafe` for Jev.
        - Never print, echo or log key values.

        ## Example: a branch

        ```toml
          [[track.step]]
          type = "branch"
          question = "How hard is this text for a text-to-speech voice to read aloud correctly?"

            [[track.step.branch]]
            name = "easy"
            when = "Plain prose that any voice reads correctly as written."

            [[track.step.branch]]
            name = "hard"
            when = "Code, paths, URLs, markdown, tables, or many figures and symbols."

              [[track.step.branch.step]]
              type = "llm"
              model = "anthropic/claude-haiku-4.5"
              prompt = "Rewrite this so it can be read aloud and understood by ear. Output only the rewritten text."
        ```

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

/// The app's "Install command-line tool": links vp into /usr/local/bin (macOS asks for the password once) or, if
/// that's declined, ~/.local/bin; then installs the agent skill everywhere it applies.
/// Keeps the command line in step with the app at each launch: the app replaces vp's target on update, but if the app
/// itself moved, links to where it was are repointed here, and the skill and hook are refreshed.
@MainActor
enum CLIMaintenance {
    /// Links to where the app used to be that couldn't be repointed (root-owned): Setup → Checks offers a fix.
    private(set) static var brokenLinks: [URL] = []

    static func run() {
        // Only an installed copy: a development build must never take over vp, the skill or the hook.
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = Bundle.main.bundleURL.resolvingSymlinksInPath().path
        guard path.hasPrefix("/Applications/") || path.hasPrefix(home + "/Applications/") else { return }
        brokenLinks = repairLinks()
        AgentsInstaller.refreshIfInstalled()
    }

    /// vp / voicepipes links whose target is gone and was a Voice Pipes (or Voice Tools) app: point them here.
    static func repairLinks(in dirs: [String] = ["/usr/local/bin", "/opt/homebrew/bin", "\(NSHomeDirectory())/.local/bin"]) -> [URL] {
        let fm = FileManager.default
        var broken: [URL] = []
        for dir in dirs {
            for name in CLI.names {
                let link = URL(fileURLWithPath: dir).appendingPathComponent(name)
                guard let target = try? fm.destinationOfSymbolicLink(atPath: link.path),
                      !fm.fileExists(atPath: link.path),  // dangling: the app it named is gone
                      target.contains(".app/Contents/MacOS/"),
                      target.contains("Voice Pipes") || target.contains("Voice Tools") else { continue }
                do {
                    try fm.removeItem(at: link)
                    try fm.createSymbolicLink(at: link, withDestinationURL: CLIInstaller.executable)
                    NSLog("VoiceTools: repointed \(link.path) at the app's new location")
                } catch {
                    broken.append(link)
                }
            }
        }
        return broken
    }

    /// The Setup check's Fix…: relink with the password prompt, then look again.
    static func fix() {
        _ = CLISetup.install()
        brokenLinks = repairLinks()
    }
}

@MainActor
enum CLISetup {
    struct State: Equatable {
        var link: URL?
        var skills: [String]   // agent names with the skill
    }

    static var state: State {
        State(link: CLIInstaller.installedLink,
              skills: AgentsInstaller.targets.filter(AgentsInstaller.isInstalled).map(\.name))
    }

    /// Returns a line describing what happened.
    static func install() -> String {
        // Quoted for the shell, then escaped for the AppleScript string around it.
        let shellQuoted = "'" + CLIInstaller.executable.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let exe = shellQuoted.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        // Never replace someone else's vp (or voicepipes) in /usr/local/bin: fall back to ~/.local/bin instead.
        let system = URL(fileURLWithPath: "/usr/local/bin")
        let taken = CLI.names.contains { name in
            let path = system.appendingPathComponent(name)  // a dangling link isn't anyone's
            return FileManager.default.fileExists(atPath: path.path) && !CLIInstaller.isVoicePipes(path)
        }
        let script = """
            do shell script "mkdir -p /usr/local/bin && ln -sfh \(exe) /usr/local/bin/vp && ln -sfh \(exe) /usr/local/bin/voicepipes" \
            with prompt "Voice Pipes wants to add its command-line tool (vp) to /usr/local/bin." with administrator privileges
            """
        var linkedTo: String
        var error: NSDictionary?
        if !taken { NSAppleScript(source: script)?.executeAndReturnError(&error) }
        if !taken, error == nil {
            linkedTo = "/usr/local/bin"
        } else {
            let fallback = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin")
            linkedTo = ((try? CLIInstaller.link(into: fallback)) != nil) ? "~/.local/bin (add it to your PATH)" : "nowhere"
        }
        let skills = (try? AgentsInstaller.installSkill())?.count ?? 0
        return "vp linked in \(linkedTo); skill installed for \(skills) agent\(skills == 1 ? "" : "s")."
    }
}

/// The card shown in Setup and the setup window: where vp is, which agents have the skill, and the button.
struct CommandLineCard: View {
    /// Given in Setup, for the read-aloud row (the setup window leaves it out).
    var store: TrackStore?
    @State private var state = CLISetup.state
    @State private var message: String?

    private static let readAloudDetail: [AgentSettings.ReadAloud: String] = [
        .off: "Agents speak only when you ask them to.",
        .long: "Agents read long replies aloud: summaries, reports, explanations.",
        .attention: "Agents speak when they're waiting on you, finish something or hit a problem, and read long replies.",
        .all: "Agents read every reply aloud, in a short spoken version.",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                StatusCode(level: state.link == nil ? .info : .ok)
                VStack(alignment: .leading, spacing: 2) {
                    Text("vp").font(VPFont.bodyStrong)
                    Text(state.link.map { "linked at \(ConfigPaths.tilde($0))" } ?? "not installed: run Voice Pipes from Terminal and agents")
                        .font(VPFont.caption).foregroundStyle(Palette.fgMuted)
                }
                Spacer()
                Button(state.link == nil ? "Install command-line tool" : "Reinstall") {
                    message = CLISetup.install()
                    state = CLISetup.state
                }
                .buttonStyle(state.link == nil ? VPButtonStyle(kind: .primary) : VPButtonStyle(kind: .secondary))
            }
            HStack(spacing: 12) {
                StatusCode(level: state.skills.isEmpty ? .info : .ok)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Agent skill").font(VPFont.bodyStrong)
                    Text(state.skills.isEmpty ? "installed with the tool, for Claude Code, Codex and other agents"
                         : "installed for " + state.skills.joined(separator: ", "))
                        .font(VPFont.caption).foregroundStyle(Palette.fgMuted)
                }
            }
            if let store {
                // The same setting as `vp agents read-aloud` and [settings.agents] read_aloud.
                let mode = Binding { store.agents.readAloud } set: { store.agents.readAloud = $0 }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Agents read to me unasked").font(VPFont.bodyStrong)
                    VPSegmented(selection: mode, options: [(.off, "Off"), (.long, "Long replies"), (.attention, "When they need me"), (.all, "Everything")])
                    Text(Self.readAloudDetail[mode.wrappedValue] ?? "").font(VPFont.caption).foregroundStyle(Palette.fgMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, 52).padding(.top, 2)
            }
            if let message { Text(message).font(VPFont.caption).foregroundStyle(Palette.green) }
            Text("Agents can then speak to you (vp say), ask you things out loud (vp ask), run your tracks and edit ~/.config/voice-pipes/config.toml.")
                .font(VPFont.caption).foregroundStyle(Palette.fgMuted).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .onAppear { state = CLISetup.state }
    }
}
