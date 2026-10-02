import Foundation

/// 1.0.0 renamed the app from Voice Tools to Voice Pipes. Sparkle installs an update where the old app was (it finds
/// the new bundle by identifier, then keeps the installed path), so an updated copy is still "Voice Tools.app" on
/// disk. On launch, rename it once to "Voice Pipes.app" in the same folder and relaunch from there. Permissions and
/// Keychain access follow the bundle identifier and signature, not the path, so nothing needs granting again.
enum BundleRename {
    static let oldName = "Voice Tools.app"
    static let newName = "Voice Pipes.app"

    /// Returns only if nothing was renamed; after a rename the process relaunches from the new path and exits.
    static func migrateIfNeeded() {
        let current = Bundle.main.bundleURL
        guard current.lastPathComponent == oldName else { return }
        let folder = current.deletingLastPathComponent()
        let target = folder.appendingPathComponent(newName)
        let files = FileManager.default
        // A read-only location (a translocated or mounted copy) or an existing Voice Pipes.app: leave it alone.
        guard files.isWritableFile(atPath: folder.path), !files.fileExists(atPath: target.path) else { return }
        do {
            try files.moveItem(at: current, to: target)
        } catch {
            NSLog("VoiceTools: couldn't rename \(current.path) to \(newName): \(error)")
            return
        }
        // Open the renamed app once this process has gone, so the two never run together.
        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
        relaunch.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", target.path]
        try? relaunch.run()
        exit(0)
    }
}
