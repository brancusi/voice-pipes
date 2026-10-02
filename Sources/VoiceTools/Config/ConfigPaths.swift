import Foundation

/// Where config.toml and friends live: `$XDG_CONFIG_HOME/voice-pipes`, else `~/.config/voice-pipes`.
enum ConfigPaths {
    static var directory: URL {
        let base = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config", isDirectory: true)
        return base.appendingPathComponent("voice-pipes", isDirectory: true)
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

/// Keeps dated copies of config.toml / vocabulary.toml before they change, newest 30 of each.
enum ConfigBackups {
    static let keep = 30

    struct Backup {
        let url: URL
        let date: Date
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
            guard name.hasPrefix(prefix), let date = ISO8601DateFormatter.backup.date(from: String(name.dropFirst(prefix.count))) else { return nil }
            return Backup(url: url, date: date)
        }
        .sorted { $0.date > $1.date }
    }
}

extension ISO8601DateFormatter {
    /// File-name safe: 2026-10-02T13-05-22Z.
    static let backup: ISO8601DateFormatter = {
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
