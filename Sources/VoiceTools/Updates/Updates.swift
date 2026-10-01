import AppKit
import Sparkle
import UserNotifications

/// Self-updating through Sparkle, which installs only updates signed with the key whose public half is built in
/// (SUPublicEDKey). Sparkle's own schedule can't be shorter than an hour, so the app also fetches the small feed
/// file (SUFeedURL) itself every few minutes and whenever the panel opens; a newer version shows in the panel,
/// turns the menu bar icon into a download arrow, and posts a notification. Install… (or clicking the
/// notification) opens Sparkle's window, which downloads, verifies the signature, and relaunches.
@MainActor
final class Updates: NSObject, ObservableObject, SPUStandardUserDriverDelegate, UNUserNotificationCenterDelegate {
    static let pollSeconds: TimeInterval = 300
    /// Set when a background check found a newer version the user hasn't looked at yet.
    @Published var available: String?

    private var controller: SPUStandardUpdaterController?
    private var feedURL: URL?
    private var timer: Timer?
    private var notified: String?          // the version we've already posted a notification for
    private var lastPoll = Date.distantPast

    /// Builds without a feed or key (local development) have updates turned off.
    var enabled: Bool { controller != nil }
    var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev" }

    override init() {
        super.init()
        let info = Bundle.main.infoDictionary ?? [:]
        guard let feed = (info["SUFeedURL"] as? String).flatMap(URL.init(string:)), info["SUPublicEDKey"] != nil else { return }
        feedURL = feed
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        poll()
    }

    /// Opens Sparkle's window: "You're up to date", or the new version with Install and Relaunch.
    func check() {
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(nil)
    }

    /// Quietly reads the feed's newest version. Called on a timer and when the panel opens (at most once a minute).
    func poll() {
        guard let feedURL, Date().timeIntervalSince(lastPoll) > 60 else { return }
        lastPoll = Date()
        var request = URLRequest(url: feedURL, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 20)
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        Task {
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let latest = Self.feedVersion(String(decoding: data, as: UTF8.self)),
                  SUStandardVersionComparator.default.compareVersion(version, toVersion: latest) == .orderedAscending
            else { return }
            available = latest
            if notified != latest {
                notified = latest
                let content = UNMutableNotificationContent()
                content.title = "Voice Tools \(latest) is available"
                content.body = "Click to install. It takes a few seconds and relaunches the app."
                content.sound = .default
                try? await UNUserNotificationCenter.current().add(
                    UNNotificationRequest(identifier: "update-\(latest)", content: content, trigger: nil))
            }
        }
    }

    nonisolated static func feedVersion(_ xml: String) -> String? {
        guard let r = xml.range(of: #"<sparkle:version>\s*([^<\s]+)\s*</sparkle:version>"#, options: .regularExpression)
        else { return nil }
        return xml[r].replacingOccurrences(of: #"</?sparkle:version>|\s"#, with: "", options: .regularExpression)
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await MainActor.run { self.check() }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    // MARK: SPUStandardUserDriverDelegate

    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Let Sparkle show its window only when the app is in front; otherwise we show it in the panel.
    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        immediateFocus
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        let version = update.displayVersionString
        Task { @MainActor in if !handleShowingUpdate { self.available = version } }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        Task { @MainActor in self.available = nil }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        Task { @MainActor in self.available = nil }
    }
}
