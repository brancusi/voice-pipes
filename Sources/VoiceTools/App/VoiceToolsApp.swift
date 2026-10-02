import SwiftUI

@main
struct VoiceToolsApp: App {
    @State private var app: AppState
    @StateObject private var updates = Updates()

    init() {
        // Before anything else starts (hotkeys, models, Sparkle): finish the Voice Tools → Voice Pipes rename.
        BundleRename.migrateIfNeeded()
        VPFont.registerBundledFonts()
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
