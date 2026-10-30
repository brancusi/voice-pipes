import AppKit

/// Pauses Apple Music and Spotify while a recording runs ([settings] pause_music), and resumes only what it paused.
///
/// Apple Events to each player, not MediaRemote: on macOS 15.4+ a third-party app can't read Now Playing, and its
/// pause commands (and synthetic Play/Pause keys) are dropped. An Apple Event reads the player's state (~12 ms),
/// so a player that wasn't playing is never started. macOS asks once per player; the prompt never comes up during
/// a take (it would take focus from the paste): a player not yet allowed is asked about when the take ends.
final class MusicPause: @unchecked Sendable {
    static let shared = MusicPause()

    struct Player: Hashable {
        let name: String
        let bundleID: String
        let suite: String  // the player's own event class for play/pause
    }

    static let players = [
        Player(name: "Music", bundleID: "com.apple.Music", suite: "hook"),
        Player(name: "Spotify", bundleID: "com.spotify.client", suite: "spfy"),
    ]

    // Confined to `queue`, so a resume always follows its pause.
    private let queue = DispatchQueue(label: "voice-pipes.music-pause")
    private var holds = 0
    private var paused: [Player] = []
    private var toAsk: Set<Player> = []

    /// A recording started: pause the players that are playing.
    func hold() {
        queue.async { [self] in
            holds += 1
            guard holds == 1 else { return }
            for player in Self.players where Self.running(player) {
                switch Self.permission(player, ask: false) {
                case noErr:
                    guard Self.isPlaying(player) else { continue }
                    if Self.send(player, "Paus") { paused.append(player) }
                case OSStatus(errAEEventWouldRequireUserConsent):
                    toAsk.insert(player)
                default:
                    continue  // refused in System Settings → Privacy & Security → Automation
                }
            }
        }
    }

    /// The recording ended: resume what `hold` paused, then ask about players macOS hasn't been told about.
    func release() {
        queue.async { [self] in
            guard holds > 0 else { return }
            holds -= 1
            guard holds == 0 else { return }
            for player in paused { _ = Self.send(player, "Play") }
            paused = []
            for player in toAsk { _ = Self.permission(player, ask: true) }
            toAsk = []
        }
    }

    /// Setup turned it on: ask now about the players that are open, rather than after the next take.
    func askForRunningPlayers() {
        queue.async {
            for player in Self.players where Self.running(player) { _ = Self.permission(player, ask: true) }
        }
    }

    // MARK: Apple Events

    private static func running(_ player: Player) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: player.bundleID).isEmpty
    }

    private static func permission(_ player: Player, ask: Bool) -> OSStatus {
        var address = AEAddressDesc()
        let id = Array(player.bundleID.utf8)
        guard AECreateDesc(typeApplicationBundleID, id, id.count, &address) == noErr else { return OSStatus(paramErr) }
        defer { AEDisposeDesc(&address) }
        return AEDeterminePermissionToAutomateTarget(&address, AEEventClass(typeWildCard), AEEventID(typeWildCard), ask)
    }

    /// `player state` is `playing` (both players use the same codes).
    private static func isPlaying(_ player: Player) -> Bool {
        let event = event(player, "core", "getd")
        let property = NSAppleEventDescriptor.record().coerce(toDescriptorType: code("obj "))!
        property.setDescriptor(NSAppleEventDescriptor(typeCode: code("prop")), forKeyword: code("want"))
        property.setDescriptor(NSAppleEventDescriptor(enumCode: code("prop")), forKeyword: code("form"))
        property.setDescriptor(NSAppleEventDescriptor(typeCode: code("pPlS")), forKeyword: code("seld"))
        property.setDescriptor(.null(), forKeyword: code("from"))
        event.setParam(property, forKeyword: keyDirectObject)
        guard let reply = try? event.sendEvent(options: [.waitForReply, .neverInteract], timeout: 1) else { return false }
        return reply.paramDescriptor(forKeyword: keyDirectObject)?.enumCodeValue == code("kPSP")
    }

    private static func send(_ player: Player, _ command: String) -> Bool {
        let event = event(player, player.suite, command)
        do {
            _ = try event.sendEvent(options: [.waitForReply, .neverInteract], timeout: 1)
            return true
        } catch {
            NSLog("VoiceTools: couldn't \(command == "Paus" ? "pause" : "resume") \(player.name): \(error.localizedDescription)")
            return false
        }
    }

    private static func event(_ player: Player, _ suite: String, _ id: String) -> NSAppleEventDescriptor {
        NSAppleEventDescriptor(eventClass: code(suite), eventID: code(id),
                               targetDescriptor: NSAppleEventDescriptor(bundleIdentifier: player.bundleID),
                               returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
    }

    private static func code(_ text: String) -> FourCharCode {
        text.utf8.reduce(0) { $0 << 8 | FourCharCode($1) }
    }
}
