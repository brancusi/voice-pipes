import AVFoundation
import AppKit
import ApplicationServices

/// One row in the Checks list.
struct Check: Identifiable {
    enum Level: Int, Comparable {
        case ok, info, warning, problem
        static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
    }

    /// Something the user can click to fix it.
    enum Fix { case microphoneSettings, accessibilitySettings, editTracks, openConfig }

    let id = UUID()
    let level: Level
    let title: String
    let detail: String
    var fix: Fix?

    var symbol: String {
        switch level {
        case .ok: "checkmark.circle.fill"
        case .info: "info.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .problem: "xmark.octagon.fill"
        }
    }
}

/// Requirement checks shown in the panel: permissions, models, keys and track configuration.
@MainActor
enum Diagnostics {
    static func run(_ app: AppState) async -> [Check] {
        var checks: [Check] = configChecks(app.store.issues, file: app.store.configURL)
            + configChecks(VocabularyStore.shared.issues, file: ConfigPaths.vocabulary)
        let tracks = app.store.tracks.filter(\.enabled)
        let steps = tracks.flatMap(\.steps).map(\.kind)

        if steps.contains(where: { if case .microphone = $0 { true } else { false } }) {
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized:
                checks.append(Check(level: .ok, title: "Microphone", detail: "Allowed"))
            case .notDetermined:
                checks.append(Check(level: .info, title: "Microphone", detail: "macOS will ask the first time you dictate."))
            default:
                checks.append(Check(level: .problem, title: "Microphone blocked",
                                    detail: "Click Fix to have macOS ask again.",
                                    fix: .microphoneSettings))
            }
        }

        checks.append(AXIsProcessTrusted()
            ? Check(level: .ok, title: "Accessibility", detail: "Allowed (paste and read selected text)")
            : Check(level: .problem, title: "Accessibility needed",
                    detail: "Needed to paste and to read selected text. Click Fix, then switch Voice Pipes on in the list that opens.",
                    fix: .accessibilitySettings))

        if steps.contains(where: { if case .parakeet = $0 { true } else { false } }) {
            switch app.parakeetState {
            case .ready: checks.append(Check(level: .ok, title: "Parakeet v3", detail: "Loaded on this Mac"))
            case .loading: checks.append(Check(level: .info, title: "Parakeet v3", detail: "Loading (first run downloads ~460 MB)…"))
            case .notLoaded: checks.append(Check(level: .info, title: "Parakeet v3", detail: "Loads on first use"))
            case .failed(let error): checks.append(Check(level: .problem, title: "Parakeet v3 failed", detail: error))
            }
        }

        let localEngines = Set(steps.compactMap { kind -> LocalVoiceEngine? in
            if case .localSpeech(let engine, _, _) = kind { engine } else { nil }
        })
        for engine in LocalVoiceEngine.allCases where localEngines.contains(engine) {
            switch app.localVoiceStates[engine] ?? .notLoaded {
            case .ready: checks.append(Check(level: .ok, title: engine.label, detail: "Loaded on this Mac"))
            case .loading: checks.append(Check(level: .info, title: engine.label, detail: "Downloading / loading (first time only)…"))
            case .notLoaded: checks.append(Check(level: .info, title: engine.label, detail: "Loads on first use"))
            case .failed(let error): checks.append(Check(level: .problem, title: "\(engine.label) failed", detail: error))
            }
        }

        if steps.contains(where: \.usesOpenRouter) {
            if !app.hasOpenRouterKey {
                checks.append(Check(level: .problem, title: "OpenRouter key missing",
                                    detail: "Add it in Voice Pipes → Setup → OpenRouter.", fix: .editTracks))
            } else {
                switch await OpenRouterClient.shared.validateKey() {
                case .valid: checks.append(Check(level: .ok, title: "OpenRouter", detail: "Key valid"))
                case .rejected: checks.append(Check(level: .problem, title: "OpenRouter key rejected",
                                                    detail: "Replace it in Voice Pipes → Setup → OpenRouter.", fix: .editTracks))
                case .unreachable: checks.append(Check(level: .warning, title: "OpenRouter unreachable",
                                                       detail: "Can't reach openrouter.ai. Cloud steps will fail until it's back."))
                }
            }
        }

        if steps.contains(where: { if case .route = $0 { true } else { false } }), !app.hasJevKey {
            checks.append(Check(level: .warning, title: "Jev key missing",
                                detail: "Route steps use their first route until you add a TypeSafe (Jev) key in Setup.", fix: .editTracks))
        }

        for combo in app.unavailableCombos {
            checks.append(Check(level: .warning, title: "\(combo.display) unavailable",
                                detail: "Another app has this shortcut. Pick a different trigger.", fix: .editTracks))
        }
        for combo in app.store.conflicts {
            checks.append(Check(level: .warning, title: "\(combo.display) used twice",
                                detail: "Only the first track with it will run.", fix: .editTracks))
        }
        for track in tracks {
            if let error = track.validationError {
                checks.append(Check(level: .warning, title: track.name, detail: error, fix: .editTracks))
            }
            if track.triggers.isEmpty {
                checks.append(Check(level: .info, title: track.name, detail: "No trigger. Run it from the panel or add one."))
            }
        }
        return checks
    }

    static func report(_ checks: [Check], tracks: [Track]) -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        var lines = ["Voice Pipes \(version) — \(Host.current().localizedName ?? "Mac") — \(ISO8601DateFormatter().string(from: Date()))",
                     "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"]
        for c in checks {
            let mark = ["ok  ", "info", "WARN", "FAIL"][c.level.rawValue]
            lines.append("\(mark)  \(c.title): \(c.detail)")
        }
        lines.append("Tracks:")
        for t in tracks {
            let triggers = t.triggers.map { "\($0.combo.display) (\($0.mode.rawValue))" }.joined(separator: ", ")
            lines.append("  \(t.enabled ? "on " : "off") \(t.name) [\(triggers)]: \(t.steps.map(\.kind.chip).joined(separator: " › "))")
        }
        return lines.joined(separator: "\n")
    }

    /// Fixes a missing permission in one click. An entry left by an older build (signed differently) shows as
    /// switched on but doesn't apply to this one, and macOS won't ask again while it exists, so clear this app's
    /// entry first; macOS then asks afresh and lists the app as it is now.
    /// config.toml / vocabulary.toml problems: one check for errors (the file isn't applied) and one for warnings.
    static func configChecks(_ issues: [ConfigIssue], file: URL) -> [Check] {
        let name = file.lastPathComponent
        var checks: [Check] = []
        let errors = issues.filter { $0.severity == .error }, warnings = issues.filter { $0.severity == .warning }
        if !errors.isEmpty {
            checks.append(Check(level: .problem, title: "\(name) not applied",
                                detail: errors.prefix(3).map(\.description).joined(separator: "\n")
                                    + (errors.count > 3 ? "\n…and \(errors.count - 3) more. `vp config check` lists them." : "")
                                    + "\nThe last good version is still running.",
                                fix: .openConfig))
        }
        if !warnings.isEmpty {
            checks.append(Check(level: .warning, title: "\(name): \(warnings.count) warning\(warnings.count == 1 ? "" : "s")",
                                detail: warnings.prefix(3).map(\.description).joined(separator: "\n"), fix: .openConfig))
        }
        return checks
    }

    static func fix(_ fix: Check.Fix) async {
        switch fix {
        case .openConfig:
            NSWorkspace.shared.open(ConfigPaths.config)
        case .accessibilitySettings:
            resetPermission("Accessibility")
            TextCapture.promptForAccessibility()
            openSettings("Privacy_Accessibility")
        case .microphoneSettings:
            resetPermission("Microphone")
            if await !AVCaptureDevice.requestAccess(for: .audio) { openSettings("Privacy_Microphone") }
        case .editTracks:
            break
        }
    }

    private static func resetPermission(_ service: String) {
        guard let id = Bundle.main.bundleIdentifier else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", service, id]
        try? process.run()
        process.waitUntilExit()
    }

    private static func openSettings(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}
