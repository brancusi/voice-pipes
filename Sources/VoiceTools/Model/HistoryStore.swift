import Foundation
import Observation

/// One finished (or failed) run: what came out, so it can be copied again later.
struct RunRecord: Codable, Identifiable, Hashable {
    struct StepTiming: Codable, Hashable {
        let title: String
        let ms: Int
        /// The step's category (Input, Transcribe, Transform, Output), for colouring the chain. Missing in runs
        /// saved before 1.4.0.
        var category: String?
    }

    var id = UUID()
    let trackName: String
    /// The track's colour when it ran. Missing in runs saved before 1.4.0.
    var colorHex: String?
    let date: Date
    /// The run's final text (what was pasted, copied or read).
    let text: String
    let totalMs: Int
    var steps: [StepTiming] = []
    /// What transcription heard, when later steps changed it (a question before its answer, raw dictation before
    /// cleanup).
    var heard: String?
    /// Why the run stopped, if it failed; `text` is then the last text it had.
    var failure: String?
}

/// Every run's text, kept on disk (`history.json` beside the tracks) so a dictation that went nowhere — focus
/// moved, paste failed — can be found and copied again, even after a restart.
@MainActor
@Observable
final class HistoryStore {
    static let limit = 1000
    nonisolated static let defaultURL = TrackStore.defaultURL.deletingLastPathComponent().appendingPathComponent("history.json")

    private(set) var records: [RunRecord] = []
    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private let writer = DispatchQueue(label: "VoiceTools.history")

    init(fileURL: URL = HistoryStore.defaultURL) {
        self.fileURL = fileURL
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            records = try JSONDecoder().decode([RunRecord].self, from: data)
        } catch {
            // Never overwrite history we can't read: keep it aside and start a new file.
            let backup = fileURL.deletingPathExtension()
                .appendingPathExtension("unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: fileURL, to: backup)
            NSLog("VoiceTools: couldn't read history (\(error)); moved it to \(backup.lastPathComponent)")
        }
    }

    func add(_ record: RunRecord) {
        records.insert(record, at: 0)
        if records.count > Self.limit { records.removeLast(records.count - Self.limit) }
        save()
    }

    func clear() {
        records = []
        save()
    }

    /// Writes off the main thread, in order, atomically.
    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        let url = fileURL
        writer.async {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }
}
