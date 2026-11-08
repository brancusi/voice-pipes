import AppKit
import Foundation

/// Uninstalling Voice Pipes (`vp uninstall`, Setup → Uninstall…). By default it keeps what you made, your dictation
/// history, pipes, config and vocabulary (plus API keys and secrets in the Keychain), and removes everything else, so
/// installing again starts like a new user's first launch: setup, permissions, model downloads, the vp link, the agent
/// skill. `everything` also moves what you made to the Trash (Finder's Put Back restores it); `keys` also removes the
/// Keychain items. Runs outside the app: it quits the app first, and trashes the app bundle last.
enum Uninstaller {
    static let bundleID = "io.github.brancusi.voice-tools"

    struct Options {
        var everything = false
        var keys = false
    }

    enum Action: String { case delete, trash }

    struct Item {
        let url: URL
        let what: String
        let action: Action
    }

    /// Left in the data folder when it's kept: the next launch runs setup as a first launch.
    static var freshStartMarker: URL { TrackStore.defaultURL.deletingLastPathComponent().appendingPathComponent(".fresh-start") }

    /// Defaults that are setup state rather than your settings; the rest (migrations already run on the kept data,
    /// the names of your secrets, appearance) stay with what's kept.
    static let setupDefaults = ["onboarding.done.v1", "SUHasLaunchedBefore", "SULastCheckTime",
                                "SUUpdateGroupIdentifier", "SUSkippedVersion", "NSNavPanelExpandedSizeForOpenMode",
                                "NSOSPLastRootDirectory"]

    /// Where the app itself is (an installed .app; nil for a development build).
    static var appBundle: URL? {
        let app = CLIInstaller.executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return app.pathExtension == "app" && Bundle(url: app)?.bundleIdentifier == bundleID ? app : nil
    }

    static func plan(_ options: Options) -> (remove: [Item], keep: [Item]) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let library = home.appendingPathComponent("Library")
        let data = TrackStore.defaultURL.deletingLastPathComponent()
        let config = ConfigPaths.directory
        func lib(_ path: String) -> URL { library.appendingPathComponent(path) }

        var remove: [Item] = [
            Item(url: home.appendingPathComponent("Library/Application Support/FluidAudio"), what: "on-device transcription models (shared with other FluidAudio apps)", action: .delete),
            Item(url: home.appendingPathComponent(".cache/fluidaudio"), what: "on-device voice models (shared with other FluidAudio apps)", action: .delete),
            Item(url: lib("Caches/\(bundleID)"), what: "caches", action: .delete),
            Item(url: lib("Caches/VoiceTools"), what: "caches", action: .delete),
            Item(url: lib("HTTPStorages/\(bundleID)"), what: "web storage", action: .delete),
            Item(url: lib("HTTPStorages/\(bundleID).binarycookies"), what: "web storage", action: .delete),
            Item(url: lib("HTTPStorages/VoiceTools"), what: "web storage", action: .delete),
            Item(url: lib("HTTPStorages/VoiceTools.binarycookies"), what: "web storage", action: .delete),
            Item(url: lib("WebKit/\(bundleID)"), what: "web storage", action: .delete),
            Item(url: lib("WebKit/VoiceTools"), what: "web storage", action: .delete),
            Item(url: lib("Saved Application State/\(bundleID).savedState"), what: "window state", action: .delete),
            Item(url: data.appendingPathComponent("supertonic-voices"), what: "Supertonic voices", action: .delete),
            Item(url: data.appendingPathComponent("models-cache.json"), what: "cloud model list", action: .delete),
            Item(url: data.appendingPathComponent("control.sock"), what: "the app's control socket", action: .delete),
            Item(url: AgentsInstaller.optOutFile, what: "agent skill opt-out", action: .delete),
        ]
        remove += AgentsInstaller.targets.filter { AgentsInstaller.isInstalled($0) }
            .map { Item(url: $0.skillFile.deletingLastPathComponent(), what: "agent skill (\($0.name))", action: .delete) }
        remove += links.map { Item(url: $0, what: "command-line link", action: .delete) }

        let mine = [
            Item(url: data, what: "dictation history, pipes, vocabulary", action: .trash),
            Item(url: config, what: "config.toml, vocabulary.toml and their backups", action: .trash),
        ]
        if options.everything { remove += mine }
        if let app = appBundle { remove.append(Item(url: app, what: "the app", action: .trash)) }
        remove = remove.filter { exists($0.url) }
        return (remove, options.everything ? [] : mine.filter { exists($0.url) })
    }

    /// vp / voicepipes links (in the usual folders) that point at a Voice Pipes app.
    static var links: [URL] {
        let rehearsal = ProcessInfo.processInfo.environment["VOICEPIPES_UNINSTALL_REHEARSAL"] == "1"
        return ((rehearsal ? [] : ["/usr/local/bin", "/opt/homebrew/bin"]) + ["\(NSHomeDirectory())/.local/bin"]).flatMap { dir in
            CLI.names.map { URL(fileURLWithPath: dir).appendingPathComponent($0) }
        }.filter { (try? FileManager.default.destinationOfSymbolicLink(atPath: $0.path)) != nil && CLIInstaller.isVoicePipes($0) }
    }

    private static func exists(_ url: URL) -> Bool {
        // A symlink counts even if what it names is gone.
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }

    struct Report {
        var removed: [Item] = []
        var failed: [(Item, String)] = []
        var kept: [Item] = []
        var permissions = ""
        var keychain = "kept"
        var hook = false
        var quitApp = false
        var everything = false
    }

    /// Does it. Quits the app first (it would write its files and preferences back as it quits).
    static func run(_ options: Options) -> Report {
        var report = Report()
        report.everything = options.everything
        // For trying it against a scratch home (CFFIXED_USER_HOME): leave the real app, permissions and Keychain be.
        let rehearsal = ProcessInfo.processInfo.environment["VOICEPIPES_UNINSTALL_REHEARSAL"] == "1"
        report.quitApp = rehearsal ? false : quitApp()
        let fm = FileManager.default
        let (remove, keep) = plan(options)
        report.kept = keep

        // The Claude Code session hook lives in a file of the user's; take out only our entry.
        if AgentsInstaller.hookInstalled, (try? AgentsInstaller.removeHook()) != nil { report.hook = true }

        for item in remove {
            do {
                switch item.action {
                case .delete: try fm.removeItem(at: item.url)
                case .trash: try fm.trashItem(at: item.url, resultingItemURL: nil)
                }
                report.removed.append(item)
            } catch {
                let reason = (error as NSError).code == NSFileWriteNoPermissionError
                    ? "needs an administrator: sudo rm \(item.url.path)" : error.localizedDescription
                report.failed.append((item, reason))
            }
        }

        // Preferences live with cfprefsd, not under the scratch home: a rehearsal would change the real ones.
        if !rehearsal, options.everything {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
            UserDefaults.standard.removePersistentDomain(forName: "VoiceTools")
        } else if !rehearsal {
            let defaults = UserDefaults(suiteName: bundleID)
            setupDefaults.forEach { defaults?.removeObject(forKey: $0) }
            CFPreferencesAppSynchronize(bundleID as CFString)
        }
        if !options.everything {
            fm.createFile(atPath: freshStartMarker.path, contents: Data("Voice Pipes was uninstalled with your data kept: the next launch runs setup as a first launch.\n".utf8))
        }

        if options.keys { report.keychain = rehearsal ? "removed (rehearsal: not really)" : Keychain.removeAll() ?? "removed" }
        if rehearsal {
            report.permissions = "reset (rehearsal: not really)"
            return report
        }

        // Microphone, Accessibility and the rest: as if never asked.
        let tcc = Process()
        tcc.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        tcc.arguments = ["reset", "All", bundleID]
        tcc.standardOutput = FileHandle.nullDevice
        tcc.standardError = FileHandle.nullDevice
        do {
            try tcc.run()
            tcc.waitUntilExit()
            report.permissions = tcc.terminationStatus == 0 ? "reset" : "not reset (tccutil exited \(tcc.terminationStatus)): remove Voice Pipes in System Settings → Privacy & Security"
        } catch {
            report.permissions = "not reset: \(error.localizedDescription)"
        }
        return report
    }

    /// Asks the running app to quit, and waits (then insists).
    private static func quitApp() -> Bool {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        guard !apps.isEmpty else { return false }
        apps.forEach { $0.terminate() }
        let deadline = Date().addingTimeInterval(8)
        while apps.contains(where: { !$0.isTerminated }), Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
        apps.filter { !$0.isTerminated }.forEach { $0.forceTerminate() }
        Thread.sleep(forTimeInterval: 0.3)
        return true
    }
}

extension VPCommands {
    /// `vp uninstall`: shows what would go (and what stays); `--yes` does it.
    static func uninstall(_ parsed: Parsed, _ out: Output) throws {
        let options = Uninstaller.Options(everything: parsed.has("everything"), keys: parsed.has("keys"))
        func rows(_ items: [Uninstaller.Item], kept: Bool = false) -> Out {
            .table(["path", "what"], items.map { [.string(ConfigPaths.tilde($0.url)), .string($0.what + (!kept && $0.action == .trash ? " (to the Trash)" : ""))] })
        }
        let keys = options.keys ? "removed" : "kept in the Keychain"
        guard parsed.has("yes") else {
            let (remove, keep) = Uninstaller.plan(options)
            out.emit(.object([
                ("dry_run", .bool(true)),
                ("would_remove", rows(remove)),
                ("would_keep", rows(keep, kept: true)),
                ("api_keys_and_secrets", .string(keys)),
                ("also", .string("resets Voice Pipes' permissions (Microphone, Accessibility) and its setup state; quits the app")),
            ]), help: ["vp uninstall --yes   (do it)", "vp uninstall --everything --yes   (also your history, pipes and config, to the Trash)"])
            return
        }
        let report = Uninstaller.run(options)
        var doc: [(String, Out)] = [
            ("uninstalled", .bool(report.failed.isEmpty)),
            ("removed", rows(report.removed)),
            ("kept", rows(report.kept, kept: true)),
            ("api_keys_and_secrets", .string(options.keys ? report.keychain : keys)),
            ("permissions", .string(report.permissions)),
            ("claude_session_hook_removed", .bool(report.hook)),
        ]
        if !report.failed.isEmpty {
            doc.append(("failed", .table(["path", "why"], report.failed.map { [.string(ConfigPaths.tilde($0.0.url)), .string($0.1)] })))
        }
        out.emit(.object(doc), help: report.kept.isEmpty ? [] : ["Install Voice Pipes again: setup runs as a first launch, with your history and pipes as they were"])
        if parsed.has("notify") { tellUser(report) }
    }

    /// From Setup → Uninstall…: the app has quit by now, so say how it went in a dialog of its own.
    private static func tellUser(_ report: Uninstaller.Report) {
        var lines = [report.everything ? "Everything was removed; your history, pipes and config are in the Trash (Put Back restores them)."
                                         : "Your dictation history, pipes and config were kept. Install Voice Pipes again to set it up from the start."]
        if report.permissions != "reset" { lines.append("Permissions: \(report.permissions)") }
        if !report.failed.isEmpty { lines.append("Couldn't remove: " + report.failed.map { "\(ConfigPaths.tilde($0.0.url)) (\($0.1))" }.joined(separator: "; ")) }
        let message = lines.joined(separator: "\n\n").replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = Process()
        script.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        script.arguments = ["-e", "display dialog \"\(message)\" with title \"Voice Pipes is uninstalled\" buttons {\"OK\"} default button 1"]
        try? script.run()
        script.waitUntilExit()
    }
}

@MainActor
enum UninstallPrompt {
    /// Setup → Uninstall…: choose what goes, then hand over to `vp uninstall`, which quits the app and finishes.
    static func show() {
        let alert = NSAlert()
        alert.messageText = "Uninstall Voice Pipes?"
        alert.informativeText = "Voice Pipes quits and is moved to the Trash, with its models, caches, permissions, setup, the vp command and the agent skill. Install it again and it starts like a first launch."
        alert.alertStyle = .warning
        let keep = NSButton(radioButtonWithTitle: "Keep my dictation history, pipes and config", target: nil, action: nil)
        let all = NSButton(radioButtonWithTitle: "Remove those too (moved to the Trash)", target: nil, action: nil)
        let keys = NSButton(checkboxWithTitle: "Also remove API keys and secrets from the Keychain", target: nil, action: nil)
        keep.state = .on
        let group = RadioGroup(keep, all)
        keep.target = group; keep.action = #selector(RadioGroup.pick(_:))
        all.target = group; all.action = #selector(RadioGroup.pick(_:))
        let stack = NSStackView(views: [keep, all, keys])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.setHuggingPriority(.defaultHigh, for: .horizontal)
        stack.frame = NSRect(x: 0, y: 0, width: 360, height: stack.fittingSize.height + 8)
        alert.accessoryView = stack
        let uninstall = alert.addButton(withTitle: "Uninstall")
        uninstall.hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        withExtendedLifetime(group) {}

        var args = ["--cli", "uninstall", "--yes", "--notify"]
        if all.state == .on { args.append("--everything") }
        if keys.state == .on { args.append("--keys") }
        let process = Process()
        process.executableURL = CLIInstaller.executable
        process.arguments = args
        // Not a pipe: it outlives the app, which it quits.
        let log = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("voice-pipes-uninstall.log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let handle = try? FileHandle(forWritingTo: log)
        process.standardOutput = handle ?? FileHandle.nullDevice
        process.standardError = handle ?? FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            let failed = NSAlert()
            failed.messageText = "Couldn't start the uninstall"
            failed.informativeText = error.localizedDescription
            failed.runModal()
        }
    }

    private final class RadioGroup: NSObject {
        let buttons: [NSButton]
        init(_ buttons: NSButton...) { self.buttons = buttons }
        @objc func pick(_ sender: NSButton) { buttons.forEach { $0.state = $0 === sender ? .on : .off } }
    }
}
