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

    /// What agents read aloud unasked ([settings.agents]); `vp agents read-aloud` sets it.
    var agents = AgentSettings() {
        didSet { if !applyingFile, agents != oldValue { save() } }
    }

    /// Whether the microphone stays open between takes ([settings] microphone); Setup edits it.
    var microphone = MicReadiness.always {
        didSet { if !applyingFile, microphone != oldValue { save() } }
    }

    /// Which mic tracks record from unless their Microphone block names one ([settings] input).
    var input = AudioInputs.system {
        didSet { if !applyingFile, input != oldValue { save() } }
    }

    /// The plain-text archive of every run ([settings.archive]); Setup edits it.
    var archive = ArchiveSettings() {
        didSet {
            guard archive != oldValue else { return }
            if !applyingFile { save() }
            onArchiveChanged(archive)
        }
    }

    /// Keyboard control while reading ([settings.reading]); Setup edits it, the file can too.
    var reading = ReadingSettings() {
        didSet { if !applyingFile, reading != oldValue { save() } }
    }

    /// Problems in config.toml as of its last read: errors (not applied) and warnings (applied).
    private(set) var issues: [ConfigIssue] = []
    /// Called when `issues` changes (AppState re-runs its checks).
    @ObservationIgnored var onIssuesChanged: () -> Void = {}
    /// After an outside edit to config.toml applies: what changed in each track that was already there.
    @ObservationIgnored var onExternalChanges: ([Track.ID: Track.Changes]) -> Void = { _ in }
    /// Called when [settings.archive] changes, from Setup or the file (AppState's archive applies it).
    @ObservationIgnored var onArchiveChanged: (ArchiveSettings) -> Void = { _ in }

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
        var loadedReading = ReadingSettings()
        var loadedAgents = AgentSettings()
        var loadedMicrophone = MicReadiness.always
        var loadedInput = AudioInputs.system
        var loadedArchive = ArchiveSettings()
        let disk = DiskText.read(configURL)
        switch disk {
        case .text(let content):
            text = content
            let result = ConfigFile.parse(content, existing: cached ?? [])
            if let config = result.config {
                loaded = config.tracks
                AppearanceChoice.store(config.appearance)
                loadedReading = config.reading
                loadedAgents = config.agents
                loadedMicrophone = config.microphone
                loadedInput = config.input
                loadedArchive = config.archive
            } else {
                // A broken file at launch: run the last good tracks and leave the file for its author to fix.
                loaded = cached ?? Track.defaults
            }
            found = result.errors + result.warnings
            // The pre-1.6 migrations are for tracks.json only; a config.toml (maybe copied from another Mac) is
            // taken as written.
            Self.markLegacyMigrationsDone()
        case .unreadable:
            loaded = cached ?? Track.defaults
            found = [ConfigIssue(severity: .error, path: "", message: "isn't readable as UTF-8 text; fix or remove it (a copy goes to backups/ before the app writes it)")]
            Self.markLegacyMigrationsDone()
        case .missing:
            if let legacy = cached {
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
        }
        var migrated = false
        if disk == .missing {
            // All three run (each is one-time, behind its own flag).
            let pocket = Self.migrateReadAloudToPocket(&loaded)
            let fixWords = Self.addFixWords(&loaded)
            let colors = Self.sundownColors(&loaded)
            migrated = pocket || fixWords || colors
        }
        // One-time (1.15.0): Quick answer joins the starters, unless a track by that name or id is already there.
        let quickAnswer = !fresh && !found.contains { $0.severity == .error } && Self.addQuickAnswer(&loaded)
        // One-time (1.8.1): the new defaults (HUD takes the keys always; agents read what needs you) reach setups
        // still on the old ones; a different choice someone made is kept.
        let newDefaults = !fresh && Self.adoptReadingDefaults(&loadedReading, &loadedAgents)
        let before = loaded
        ConfigFile.assignSlugs(&loaded)
        let changed = migrated || newDefaults || quickAnswer || loaded != before
        tracks = loaded
        reading = loadedReading
        agents = loadedAgents
        microphone = loadedMicrophone
        input = loadedInput
        archive = loadedArchive
        issues = found
        diskText = text
        createdFresh = fresh
        // Write the file when there's none yet, or a fix-up changed tracks in a file that checks out.
        if disk == .missing || (changed && !found.contains { $0.severity == .error }) { save() }
        ConfigPaths.writeSchemas(in: configURL.deletingLastPathComponent())
        if watch { watcher = FileWatcher(configURL) { [weak self] in self?.reloadFromDisk() } }
    }

    /// Adds the Quick answer starter after Read aloud (or at the end), once. A track named "Quick answer" or with
    /// its id stays exactly as it is, and nothing is added. Its hotkey is left off if another track uses it.
    static func addQuickAnswer(_ tracks: inout [Track]) -> Bool {
        let key = "migration.quickAnswerStarter.v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return false }
        UserDefaults.standard.set(true, forKey: key)
        guard !tracks.contains(where: { $0.slug == "quick-answer" || $0.name.caseInsensitiveCompare("Quick answer") == .orderedSame }) else { return false }
        var starter = Track.quickAnswer.copied(named: "Quick answer")
        starter.enabled = true
        let taken = Set(tracks.flatMap(\.triggers).map(\.combo))
        starter.triggers.removeAll { taken.contains($0.combo) }
        let at = tracks.firstIndex { $0.name == "Read aloud" }.map { $0 + 1 } ?? tracks.count
        tracks.insert(starter, at: at)
        return true
    }

    private static func adoptReadingDefaults(_ reading: inout ReadingSettings, _ agents: inout AgentSettings) -> Bool {
        let key = "migration.readingDefaults.v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return false }
        UserDefaults.standard.set(true, forKey: key)
        var changed = false
        if reading.takeKeys == .hover { reading.takeKeys = .always; changed = true }
        if agents.readAloud == .off { agents.readAloud = .attention; changed = true }
        return changed
    }

    private static func markLegacyMigrationsDone() {
        for key in ["migration.readAloudPocket.v1", "migration.fixWords.v1", "migration.sundownColors.v1"] {
            UserDefaults.standard.set(true, forKey: key)
        }
    }

    /// Writes config.toml now (after a settings change such as Appearance).
    func saveConfig() { save() }

    /// Re-reads config.toml if it changed outside the app. `vp config reload` and the watcher call this.
    func reloadFromDisk() {
        let text: String
        switch DiskText.read(configURL) {
        case .text(let t): text = t
        case .unreadable:
            setIssues([ConfigIssue(severity: .error, path: "", message: "isn't readable as UTF-8 text; fix or remove it (a copy goes to backups/ before the app writes it)")])
            return
        case .missing: return
        }
        guard text != diskText else { return }
        if let previous = diskText { ConfigBackups.save(previous, of: configURL, in: backupsURL) }
        diskText = text
        let result = ConfigFile.parse(text, existing: tracks)
        if let config = result.config {
            var updated = config.tracks
            var changes: [Track.ID: Track.Changes] = [:]
            for i in updated.indices {
                guard let old = tracks.first(where: { $0.id == updated[i].id }) else { continue }
                let changed = updated[i].adoptIdentities(from: old)
                if !changed.isEmpty { changes[updated[i].id] = changed }
            }
            applyingFile = true
            tracks = updated
            applyingFile = false
            AppearanceChoice.store(config.appearance)
            applyingFile = true
            reading = config.reading
            agents = config.agents
            microphone = config.microphone
            input = config.input
            archive = config.archive
            applyingFile = false
            writeCache()
            if !changes.isEmpty { onExternalChanges(changes) }
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

    /// Copies a track (named "… copy", disabled) right after it; returns the copy's id.
    @discardableResult
    func duplicate(_ id: Track.ID) -> Track.ID? {
        guard let index = tracks.firstIndex(where: { $0.id == id }) else { return nil }
        let names = Set(tracks.map(\.name))
        var name = "\(tracks[index].name) copy", n = 2
        while names.contains(name) { name = "\(tracks[index].name) copy \(n)"; n += 1 }
        let copy = tracks[index].copied(named: name)
        tracks.insert(copy, at: index + 1)
        return copy.id
    }

    /// The enabled tracks (other than this one) that already use one of this track's hotkeys.
    func clashes(for id: Track.ID) -> [(combo: KeyCombo, track: Track)] {
        guard let track = tracks.first(where: { $0.id == id }) else { return [] }
        var found: [(KeyCombo, Track)] = []
        for combo in Set(track.triggers.map(\.combo)) {
            for other in tracks where other.id != id && other.enabled && other.triggers.contains(where: { $0.combo == combo }) {
                found.append((combo, other))
            }
        }
        return found.sorted { $0.0.display < $1.0.display }
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
        let text = ConfigFile.write(AppConfig(appearance: AppearanceChoice.current, microphone: microphone, input: input, reading: reading, agents: agents, archive: archive, tracks: tracks))
        guard text != diskText else { return }
        do {
            try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            ConfigBackups.beforeWrite(configURL, ours: diskText, broken: issues.contains { $0.severity == .error }, in: backupsURL)
            try writeConfigText(text, to: configURL)
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
