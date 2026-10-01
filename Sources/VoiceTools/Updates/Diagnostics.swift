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
    enum Fix { case microphoneSettings, accessibilitySettings, editTracks }

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
        var checks: [Check] = []
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
                    detail: "Needed to paste and to read selected text. Click Fix, then switch Voice Tools on in the list that opens.",
                    fix: .accessibilitySettings))

        if steps.contains(where: { if case .parakeet = $0 { true } else { false } }) {
            switch app.parakeetState {
            case .ready: checks.append(Check(level: .ok, title: "Parakeet v3", detail: "Loaded on this Mac"))
            case .loading: checks.append(Check(level: .info, title: "Parakeet v3", detail: "Loading (first run downloads ~460 MB)…"))
            case .notLoaded: checks.append(Check(level: .info, title: "Parakeet v3", detail: "Loads on first use"))
            case .failed(let error): checks.append(Check(level: .problem, title: "Parakeet v3 failed", detail: error))
            }
        }

        if steps.contains(where: \.usesOpenRouter) {
            if !app.hasOpenRouterKey {
                checks.append(Check(level: .problem, title: "OpenRouter key missing",
                                    detail: "Add it in Edit tracks → Connections.", fix: .editTracks))
            } else {
                switch await OpenRouterClient.shared.validateKey() {
                case .valid: checks.append(Check(level: .ok, title: "OpenRouter", detail: "Key valid"))
                case .rejected: checks.append(Check(level: .problem, title: "OpenRouter key rejected",
                                                    detail: "Replace it in Edit tracks → Connections.", fix: .editTracks))
                case .unreachable: checks.append(Check(level: .warning, title: "OpenRouter unreachable",
                                                       detail: "Can't reach openrouter.ai. Cloud steps will fail until it's back."))
                }
            }
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
        var lines = ["Voice Tools \(version) — \(Host.current().localizedName ?? "Mac") — \(ISO8601DateFormatter().string(from: Date()))",
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
    static func fix(_ fix: Check.Fix) async {
        switch fix {
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
