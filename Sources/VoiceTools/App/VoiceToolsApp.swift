import SwiftUI

@main
struct VoiceToolsApp: App {
    @State private var app: AppState
    @StateObject private var updates = Updates()

    init() {
        // Before anything else starts (hotkeys, models, Sparkle): finish the Voice Tools → Voice Pipes rename.
        BundleRename.migrateIfNeeded()
        _app = State(initialValue: AppState())
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
    }

    /// The pixel pipes, except while reading aloud (a speaker) or when something needs fixing (a warning).
    /// An update waiting adds a dot until it's looked at.
    @ViewBuilder private var menuBarIcon: some View {
        switch app.run?.phase {
        case .recording: Image(nsImage: MenuBarGlyph.image(.recording))
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
