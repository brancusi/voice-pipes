import Foundation
import Observation

/// The tracks, kept in ~/.config/voice-pipes/config.toml (with the settings). Saves in the app write the canonical
/// file; edits to the file from anywhere else (an editor, an agent, `vp`) apply within a second. A file that doesn't
/// check out never applies: the last good tracks keep running and `issues` says why. tracks.json (Application
/// Support) holds a copy of the last good tracks, so even a broken file at launch has something to run.
@MainActor
@Observable
final class TrackStore {
    var tracks: [Track] {
        didSet { if !applyingFile { save() } }
    }

    /// Problems in config.toml as of its last read: errors (not applied) and warnings (applied).
    private(set) var issues: [ConfigIssue] = []
    /// Called when `issues` changes (AppState re-runs its checks).
    @ObservationIgnored var onIssuesChanged: () -> Void = {}

    let fileURL: URL
    let configURL: URL
    /// True when there was no tracks file yet: a first launch on this Mac.
    private(set) var createdFresh = false

    @ObservationIgnored private var applyingFile = false
    /// The file's text as last read or written, so our own writes aren't re-applied.
    @ObservationIgnored private var diskText: String?
    @ObservationIgnored private var watcher: FileWatcher?

    /// `fileURL` is the last-good copy (and, from before 1.6.0, the only file); `configURL` the TOML.
    init(fileURL: URL = TrackStore.defaultURL, configURL: URL = ConfigPaths.config, watch: Bool = true) {
        self.fileURL = fileURL
        self.configURL = configURL
        // Everything happens on a local copy: changing `tracks` itself would save, and must not overwrite a file
        // that doesn't check out.
        let cached = Self.readCache(fileURL)
        var loaded: [Track]
        var text: String?
        var found: [ConfigIssue] = []
        var fresh = false
        if let disk = try? String(contentsOf: configURL, encoding: .utf8) {
            text = disk
            let result = ConfigFile.parse(disk, existing: cached ?? [])
            if let config = result.config {
                loaded = config.tracks
                AppearanceChoice.store(config.appearance)
            } else {
                // A broken file at launch: run the last good tracks and leave the file for its author to fix.
                loaded = cached ?? Track.defaults
            }
            found = result.errors + result.warnings
        } else if let legacy = cached {
            // 1.6.0: tracks move from tracks.json to config.toml, once. tracks.json stays as the last-good copy.
            loaded = legacy
        } else if FileManager.default.fileExists(atPath: fileURL.path) {
            // Never overwrite tracks we can't read: keep them aside, then start from the defaults.
            let backup = fileURL.deletingPathExtension()
                .appendingPathExtension("unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: fileURL, to: backup)
            NSLog("VoiceTools: couldn't read tracks; moved them to \(backup.lastPathComponent)")
            loaded = Track.defaults
        } else {
            loaded = Track.defaults
            fresh = true
        }
        // All three run (each is one-time, behind its own flag).
        let pocket = Self.migrateReadAloudToPocket(&loaded)
        let fixWords = Self.addFixWords(&loaded)
        let colors = Self.sundownColors(&loaded)
        let migrated = pocket || fixWords || colors
        let before = loaded
        ConfigFile.assignSlugs(&loaded)
        let changed = migrated || loaded != before
        tracks = loaded
        issues = found
        diskText = text
        createdFresh = fresh
        // Write the file when there's none yet or a migration changed something, but never over a broken file.
        if text == nil || (changed && !found.contains { $0.severity == .error }) { save() }
        ConfigPaths.writeSchemas(in: configURL.deletingLastPathComponent())
        if watch { watcher = FileWatcher(configURL) { [weak self] in self?.reloadFromDisk() } }
    }

    /// Writes config.toml now (after a settings change such as Appearance).
    func saveConfig() { save() }

    /// Re-reads config.toml if it changed outside the app. `vp config reload` and the watcher call this.
    func reloadFromDisk() {
        guard let text = try? String(contentsOf: configURL, encoding: .utf8), text != diskText else { return }
        if let previous = diskText { ConfigBackups.save(previous, of: configURL, in: backupsURL) }
        diskText = text
        let result = ConfigFile.parse(text, existing: tracks)
        if let config = result.config {
            applyingFile = true
            tracks = config.tracks
            applyingFile = false
            AppearanceChoice.store(config.appearance)
            writeCache()
        }
        setIssues(result.errors + result.warnings)
    }

    private var backupsURL: URL { configURL.deletingLastPathComponent().appendingPathComponent("backups", isDirectory: true) }

    private func setIssues(_ new: [ConfigIssue]) {
        guard new != issues else { return }
        issues = new
        onIssuesChanged()
    }

    private static func readCache(_ url: URL) -> [Track]? {
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([Track].self, from: $0) }
    }

    /// One-time (0.5.1): Pocket TTS became the default Read aloud voice. Switch an existing "Read aloud" track's
    /// macOS or OpenRouter Speak step to it, keeping the speed. Later changes by the user are left alone.
    private static func migrateReadAloudToPocket(_ tracks: inout [Track]) -> Bool {
        let key = "migration.readAloudPocket.v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return false }
        UserDefaults.standard.set(true, forKey: key)
        var changed = false
        for i in tracks.indices where tracks[i].name == "Read aloud" {
            for j in tracks[i].steps.indices {
                switch tracks[i].steps[j].kind {
                case .speak(_, let rate), .openRouterSpeech(_, _, let rate):
                    tracks[i].steps[j].kind = .localSpeech(engine: .pocket, voice: LocalVoiceEngine.pocket.defaultVoice, rate: rate)
                    changed = true
                default:
                    break
                }
            }
        }
        return changed
    }

    /// One-time (0.6.0): put a Fix words step right after the transcription step of every dictation track.
    private static func addFixWords(_ tracks: inout [Track]) -> Bool {
        let key = "migration.fixWords.v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return false }
        UserDefaults.standard.set(true, forKey: key)
        var changed = false
        for i in tracks.indices where !tracks[i].steps.contains(where: { $0.kind == .fixWords }) {
            guard let index = tracks[i].steps.firstIndex(where: {
                switch $0.kind { case .parakeet, .openRouterSTT: true; default: false }
            }) else { continue }
            tracks[i].steps.insert(Step(kind: .fixWords), at: index + 1)
            changed = true
        }
        return changed
    }

    /// One-time (1.4.0): the old default track colours become their Sundown palette colours (which also switch to
    /// their Daylight versions in light mode). Colours the user picked themselves are left alone.
    private static func sundownColors(_ tracks: inout [Track]) -> Bool {
        let key = "migration.sundownColors.v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return false }
        UserDefaults.standard.set(true, forKey: key)
        let map = ["#D9731A": "#F0A35E", "#0A66D8": "#8FB8D6", "#6B4FD1": "#C3A3D4", "#1F9D55": "#A9BF8A"]
        var changed = false
        for i in tracks.indices {
            if let new = map[tracks[i].colorHex.uppercased()] {
                tracks[i].colorHex = new
                changed = true
            }
        }
        return changed
    }

    nonisolated static var defaultURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VoiceTools", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("tracks.json")
    }

    /// Adds back the starter tracks (Track.defaults) with fresh ids. A starter's hotkey that another track already
    /// uses is left off rather than creating a clash.
    func restoreStarters() {
        var taken = Set(tracks.flatMap(\.triggers).map(\.combo))
        var added: [Track] = []
        for starter in Track.defaults {
            var track = starter
            track.id = UUID()
            track.steps = track.steps.map { var step = $0; step.id = UUID(); return step }
            track.triggers = track.triggers.compactMap { trigger in
                guard taken.insert(trigger.combo).inserted else { return nil }
                var fresh = trigger
                fresh.id = UUID()
                return fresh
            }
            added.append(track)
        }
        tracks.append(contentsOf: added)
    }

    /// Triggers bound to more than one place, keyed by combo.
    var conflicts: Set<KeyCombo> {
        var seen = Set<KeyCombo>(), dupes = Set<KeyCombo>()
        for combo in tracks.filter(\.enabled).flatMap(\.triggers).map(\.combo) where !seen.insert(combo).inserted {
            dupes.insert(combo)
        }
        return dupes
    }

    /// Writes the canonical config.toml (and the last-good copy). Backs up the file's previous text first, at most
    /// once a minute, so typing a track name doesn't fill the backups.
    private func save() {
        // New or renamed-from-blank tracks get an id; assigned without re-entering save().
        var slugged = tracks
        ConfigFile.assignSlugs(&slugged)
        if slugged != tracks {
            applyingFile = true
            tracks = slugged
            applyingFile = false
        }
        let text = ConfigFile.write(AppConfig(appearance: AppearanceChoice.current, tracks: tracks))
        guard text != diskText else { return }
        do {
            try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let previous = diskText { ConfigBackups.save(previous, of: configURL, minimumGap: 60, in: backupsURL) }
            try text.write(to: configURL, atomically: true, encoding: .utf8)
            diskText = text
            watcher?.noteWrite(configURL)
            writeCache()
            setIssues([])
        } catch {
            NSLog("VoiceTools: failed to save config.toml: \(error)")
        }
    }

    private func writeCache() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(tracks).write(to: fileURL, options: .atomic)
    }
}
