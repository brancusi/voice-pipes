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
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([Track].self, from: data) {
            tracks = decoded
        } else {
            tracks = Track.defaults
            save()
        }
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
