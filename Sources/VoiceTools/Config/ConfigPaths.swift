import Foundation

/// Where config.toml and friends live: always `~/.config/voice-pipes`. Not `$XDG_CONFIG_HOME`: the app is launched
/// by launchd, which doesn't see a shell's environment, so the app and `vp` could disagree about the path.
enum ConfigPaths {
    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config", isDirectory: true).appendingPathComponent("voice-pipes", isDirectory: true)
    }

    static var config: URL { directory.appendingPathComponent("config.toml") }
    static var vocabulary: URL { directory.appendingPathComponent("vocabulary.toml") }
    static var backups: URL { directory.appendingPathComponent("backups", isDirectory: true) }

    /// Writes the schemas beside the files (they're referenced by `#:schema ./…` at the top of each).
    static func writeSchemas(in directory: URL = directory) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, text) in [("config.schema.json", ConfigSchema.config), ("vocabulary.schema.json", ConfigSchema.vocabulary)] {
            let url = directory.appendingPathComponent(name)
            if (try? String(contentsOf: url, encoding: .utf8)) != text { try? text.write(to: url, atomically: true, encoding: .utf8) }
        }
    }

    /// `~/.config/voice-pipes/config.toml` for display.
    static func tilde(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return url.path.hasPrefix(home) ? "~" + url.path.dropFirst(home.count) : url.path
    }
}

/// Keeps dated copies of config.toml / vocabulary.toml before they change, newest 50 of each.
enum ConfigBackups {
    static let keep = 50

    struct Backup {
        let url: URL
        let date: Date
    }

    /// A file that exists but isn't readable text: keep its bytes before anything replaces it.
    static func saveRaw(_ file: URL, in directory: URL = ConfigPaths.backups) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter.backup.string(from: Date())
        let name = "\(file.deletingPathExtension().lastPathComponent)-\(stamp).\(file.pathExtension)"
        try? FileManager.default.copyItem(at: file.resolvingSymlinksInPath(), to: directory.appendingPathComponent(name))
    }

    /// Before the app writes `file`: back up what's there. Text we wrote ourselves is backed up at most once a minute;
    /// anything else (an outside edit the watcher hasn't applied yet, a broken edit, unreadable bytes) always.
    static func beforeWrite(_ file: URL, ours: String?, broken: Bool, in directory: URL) {
        switch DiskText.read(file) {
        case .text(let current) where current != ours || broken: save(current, of: file, in: directory)
        case .text(let current): save(current, of: file, minimumGap: 60, in: directory)
        case .unreadable: saveRaw(file, in: directory)
        case .missing: break
        }
    }

    /// Copies `text` (the version about to be replaced) into backups/, unless one was made less than `minimumGap` ago.
    static func save(_ text: String, of file: URL, minimumGap: TimeInterval = 0, in directory: URL = ConfigPaths.backups) {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let existing = list(of: file, in: directory)
        if let newest = existing.first, Date().timeIntervalSince(newest.date) < minimumGap { return }
        if let newest = existing.first, (try? String(contentsOf: newest.url, encoding: .utf8)) == text { return }
        let stamp = ISO8601DateFormatter.backup.string(from: Date())
        let name = "\(file.deletingPathExtension().lastPathComponent)-\(stamp).\(file.pathExtension)"
        try? text.write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
        for old in list(of: file, in: directory).dropFirst(keep) { try? fm.removeItem(at: old.url) }
    }

    /// Newest first.
    static func list(of file: URL, in directory: URL = ConfigPaths.backups) -> [Backup] {
        let prefix = file.deletingPathExtension().lastPathComponent + "-"
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return urls.compactMap { url -> Backup? in
            let name = url.deletingPathExtension().lastPathComponent
            let stamp = String(name.dropFirst(prefix.count))
            guard name.hasPrefix(prefix),
                  let date = ISO8601DateFormatter.backup.date(from: stamp) ?? ISO8601DateFormatter.backupSeconds.date(from: stamp)
            else { return nil }
            return Backup(url: url, date: date)
        }
        .sorted { $0.date > $1.date }
    }
}

extension ISO8601DateFormatter {
    /// File-name safe, to the millisecond: 2026-10-02T130522.123Z.
    static let backup: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate, .withTime, .withFractionalSeconds, .withTimeZone]
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    /// The 1.6.0 beta stamp (whole seconds), still read so older backups are listed and pruned.
    static let backupSeconds: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate, .withTime, .withTimeZone]
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()
}

/// Polls a file's modification date and size once a second and calls back when they change. Polling (not
/// directory events) also catches in-place edits like `>>` appends; the cost is one stat per second.
@MainActor
final class FileWatcher {
    private var timer: Timer?
    private var last: (Date?, Int?)

    init(_ url: URL, onChange: @escaping @MainActor () -> Void) {
        last = Self.stamp(url)
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let now = Self.stamp(url)
                if now.0 != self.last.0 || now.1 != self.last.1 {
                    self.last = now
                    onChange()
                }
            }
        }
    }

    /// Call after writing the file yourself, so your own write isn't reported.
    func noteWrite(_ url: URL) { last = Self.stamp(url) }

    private static func stamp(_ url: URL) -> (Date?, Int?) {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.modificationDate] as? Date, (attributes?[.size] as? NSNumber)?.intValue)
    }

    deinit { timer?.invalidate() }
}

/// What's on disk at a config path.
enum DiskText: Equatable {
    case missing
    case unreadable
    case text(String)

    static func read(_ url: URL) -> DiskText {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        return (try? String(contentsOf: url, encoding: .utf8)).map(DiskText.text) ?? .unreadable
    }
}

/// Writes through a symlink (a config kept in a dotfiles repo stays linked), atomically.
func writeConfigText(_ text: String, to url: URL) throws {
    try text.write(to: url.resolvingSymlinksInPath(), atomically: true, encoding: .utf8)
}
