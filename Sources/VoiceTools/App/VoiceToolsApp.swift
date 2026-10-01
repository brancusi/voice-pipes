import SwiftUI

@main
struct VoiceToolsApp: App {
    @State private var app = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuView(app: app)
        } label: {
            Image(systemName: menuBarSymbol)
        }
        .menuBarExtraStyle(.window)

        Window("Tracks", id: "tracks") {
            TrackEditorView(app: app)
        }
        .windowResizability(.contentMinSize)
    }

    private var menuBarSymbol: String {
        switch app.run?.phase {
        case .recording: "mic.fill"
        case .processing: "ellipsis.circle"
        case .speaking: "speaker.wave.2.fill"
        default: "mic"
        }
    }
}
