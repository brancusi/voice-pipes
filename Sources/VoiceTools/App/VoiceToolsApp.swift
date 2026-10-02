import SwiftUI

/// One binary, two faces: run as `vp` / `voicepipes` (a symlink) it's the command-line tool; otherwise the app.
@main
enum Entry {
    static func main() {
        if CLI.isInvocation { CLI.main() }
        VoiceToolsApp.main()
    }
}

struct VoiceToolsApp: App {
    @State private var app: AppState
    @StateObject private var updates = Updates()

    init() {
        // Before anything else starts (hotkeys, models, Sparkle): finish the Voice Tools → Voice Pipes rename.
        BundleRename.migrateIfNeeded()
        VPFont.registerBundledFonts()
        // vp follows the app on update; if the app moved, its links, the agent skill and the hook catch up here.
        CLIMaintenance.run()
        let state = AppState()
        _app = State(initialValue: state)
        // Light, dark or Auto, as chosen in Setup → Appearance; then the setup window on a first launch.
        DispatchQueue.main.async {
            AppearanceChoice.apply()
            if state.needsOnboarding { OnboardingController.shared.show(state) }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView(app: app).environmentObject(updates)
        } label: {
            menuBarIcon
                .modifier(WindowRequests(updates: updates))
        }
        .menuBarExtraStyle(.window)

        Window("Voice Pipes", id: "main") {
            MainWindowView(app: app).environmentObject(updates)
        }
        .defaultSize(width: 1100, height: 760)
        .windowResizability(.contentMinSize)
        .commands { AboutCommand() }

        Window("About Voice Pipes", id: "about") {
            AboutView(app: app).environmentObject(updates)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
    }

    /// The Wrangler: a bust in his hat, swinging a lasso while recording. A speaker while reading aloud, a warning
    /// when something needs fixing; an update waiting adds a dot until it's looked at.
    @ViewBuilder private var menuBarIcon: some View {
        switch app.run?.phase {
        case .recording: Image(nsImage: MenuBarGlyph.image(.lasso(app.lassoFrame)))
        case .speaking: Image(systemName: "speaker.wave.2.fill")
        default:
            if app.run == nil, app.worstCheck == .problem {
                Image(systemName: "exclamationmark.triangle")
            } else {
                Image(nsImage: MenuBarGlyph.image(updates.available != nil && app.run == nil ? .update : .idle))
            }
        }
    }
}

/// The app menu's "About Voice Pipes" opens our About window instead of the standard panel.
private struct AboutCommand: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Voice Pipes") {
                openWindow(id: "about")
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}

/// Opens windows and checks for updates when `vp` asks (the menu bar icon is the one view that always exists, and
/// SwiftUI only lets views open windows).
private struct WindowRequests: ViewModifier {
    let updates: Updates
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .voicePipesOpenWindow)) { note in
                openWindow(id: note.object as? String ?? "main")
                if UINav.shared.quietOpen {
                    // Shown, not focused: put it in front of other apps' windows without activating.
                    DispatchQueue.main.async {
                        NSApp.windows.first { $0.identifier?.rawValue.hasPrefix(note.object as? String ?? "main") == true }?.orderFrontRegardless()
                    }
                } else {
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .voicePipesCheckForUpdates)) { _ in updates.check() }
    }
}
