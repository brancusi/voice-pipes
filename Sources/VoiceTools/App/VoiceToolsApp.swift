import SwiftUI

@main
struct VoiceToolsApp: App {
    @State private var app = AppState()
    @StateObject private var updates = Updates()

    var body: some Scene {
        MenuBarExtra {
            MenuView(app: app).environmentObject(updates)
        } label: {
            // An update waiting shows as a download arrow until it's looked at.
            Image(systemName: updates.available != nil && app.run == nil ? "arrow.down.circle" : menuBarSymbol)
        }
        .menuBarExtraStyle(.window)

        Window("Voice Tools", id: "main") {
            MainWindowView(app: app).environmentObject(updates)
        }
        .defaultSize(width: 1100, height: 760)
        .windowResizability(.contentMinSize)
    }

    private var menuBarSymbol: String {
        switch app.run?.phase {
        case .recording: "mic.fill"
        case .processing: "ellipsis.circle"
        case .speaking: "speaker.wave.2.fill"
        default: app.worstCheck == .problem ? "mic.badge.xmark" : "mic"
        }
    }
}
