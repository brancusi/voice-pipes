import Foundation
import Observation

/// Loads and saves tracks as JSON in Application Support so they can also be edited by hand.
@MainActor
@Observable
final class TrackStore {
    var tracks: [Track] {
        didSet { save() }
    }

    let fileURL: URL

    init(fileURL: URL = TrackStore.defaultURL) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL) {
            do {
                tracks = try JSONDecoder().decode([Track].self, from: data)
                let pocket = Self.migrateReadAloudToPocket(&tracks)
                let fixWords = Self.addFixWords(&tracks)
                if pocket || fixWords { save() }
            } catch {
                // Never overwrite tracks we can't read: keep them aside, then start from the defaults.
                let backup = fileURL.deletingPathExtension()
                    .appendingPathExtension("unreadable-\(Int(Date().timeIntervalSince1970)).json")
                try? FileManager.default.moveItem(at: fileURL, to: backup)
                NSLog("VoiceTools: couldn't read tracks (\(error)); moved them to \(backup.lastPathComponent)")
                tracks = Track.defaults
                save()
            }
        } else {
            tracks = Track.defaults
            save()
        }
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

    nonisolated static var defaultURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VoiceTools", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("tracks.json")
    }

    /// Triggers bound to more than one place, keyed by combo.
    var conflicts: Set<KeyCombo> {
        var seen = Set<KeyCombo>(), dupes = Set<KeyCombo>()
        for combo in tracks.filter(\.enabled).flatMap(\.triggers).map(\.combo) where !seen.insert(combo).inserted {
            dupes.insert(combo)
        }
        return dupes
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try encoder.encode(tracks).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("VoiceTools: failed to save tracks: \(error)")
        }
    }
}
