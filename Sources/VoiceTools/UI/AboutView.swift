import SwiftUI

/// About Voice Pipes: the Wrangler busking beside the organ pipes at sundown, then the wordmark, version, what it is,
/// the hotkeys you have set up, and the way to release notes and updates.
struct AboutView: View {
    let app: AppState
    @EnvironmentObject var updates: Updates
    @Environment(\.openURL) private var openURL

    static let releaseNotes = URL(string: "https://github.com/brancusi/voice-tools-releases/releases")!

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SundownScene()
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Wordmark(size: 34, weight: .medium)
                    Text(updates.enabled ? "\(updates.version) · signed and notarized" : "\(updates.version) · development build")
                        .font(.system(size: 12, design: .monospaced)).foregroundStyle(Palette.fgMuted)
                }
                Text("A cowboy hacker's instrument. Pipelines you play from the keyboard: hold a hotkey, talk, and your words run through Parakeet, your vocabulary and a model or two, then out at the cursor.")
                    .font(VPFont.body).lineSpacing(3).foregroundStyle(Palette.fgMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 640, alignment: .leading)
                if !hotkeys.isEmpty {
                    HStack(spacing: 10) {
                        ForEach(Array(hotkeys.enumerated()), id: \.offset) { index, item in
                            if index > 0 { Text("·").foregroundStyle(Palette.comment) }
                            Keycap(text: item.0)
                            Text(item.1.lowercased()).foregroundStyle(Palette.fgMuted)
                        }
                    }
                    .font(.system(size: 12, design: .monospaced))
                }
                HStack(spacing: 10) {
                    Button("Release notes") { openURL(Self.releaseNotes) }.buttonStyle(.vpPrimary)
                        .keyboardShortcut(.defaultAction)
                    Button("Check for updates") { updates.check() }.buttonStyle(.vpSecondary).disabled(!updates.enabled)
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 32).padding(.top, 24).padding(.bottom, 28)
        }
        .frame(width: SundownScene.size.width)
        .background(Palette.bg100)
        .vpWindow()
        .background(WindowBehavior())
        .onAppear { WindowBehavior.opened() }
        .onDisappear { WindowBehavior.closed() }
    }

    /// The first hotkey of up to three enabled tracks.
    private var hotkeys: [(String, String)] {
        Array(app.store.tracks.filter(\.enabled).compactMap { track in
            track.triggers.first.map { ($0.combo.display, track.name) }
        }.prefix(3))
    }
}

/// The pixel sundown: sky bands, the sun behind a mesa, five organ pipes on their base pipe, and the Wrangler
/// busking. `.about` is the full 76 × 30 scene; `.welcome` is the setup window's shorter 76 × 24 banner. Drawn from
/// the app mockups' pixel layouts at 10×; whole pixels only.
struct SundownScene: View {
    enum Layout { case about, welcome }
    var layout: Layout = .about

    static let scale: CGFloat = 10
    static let size = CGSize(width: 76 * scale, height: 30 * scale)

    private typealias Px = (x: Int, y: Int, w: Int, h: Int, color: UInt32)

    private static let about: [Px] = [
        (0, 0, 76, 5, 0x2A2140), (0, 5, 76, 4, 0x43294A), (0, 9, 76, 4, 0x6B3A52), (0, 13, 76, 3, 0x9A4E55),
        (0, 16, 76, 3, 0xC96A57), (0, 19, 76, 2, 0xE8915F), (0, 21, 76, 2, 0xF2B46A), (0, 23, 76, 7, 0x1F1A15),
        (9, 2, 1, 1, 0xF0E4CC), (66, 3, 1, 1, 0xF0E4CC), (38, 1, 1, 1, 0xC3A3D4),
        (58, 14, 4, 1, 0xF6D58A), (57, 15, 6, 4, 0xF6D58A), (58, 19, 4, 1, 0xF6D58A),
        (52, 18, 14, 1, 0x2B1F24), (49, 19, 22, 4, 0x2B1F24),
        (41, 13, 3, 11, 0x18140F), (45, 9, 3, 15, 0x18140F), (49, 6, 3, 18, 0x18140F), (53, 10, 3, 14, 0x18140F),
        (57, 14, 3, 10, 0x18140F),
        (42, 17, 1, 1, 0xC96A57), (46, 17, 1, 1, 0xC96A57), (50, 17, 1, 1, 0xC96A57), (54, 17, 1, 1, 0xC96A57),
        (58, 17, 1, 1, 0xC96A57),
        (40, 24, 21, 1, 0xF0E4CC),
    ]

    private static let welcome: [Px] = [
        (0, 0, 76, 3, 0x2A2140), (0, 3, 76, 3, 0x43294A), (0, 6, 76, 3, 0x6B3A52), (0, 9, 76, 3, 0x9A4E55),
        (0, 12, 76, 3, 0xC96A57), (0, 15, 76, 2, 0xE8915F), (0, 17, 76, 2, 0xF2B46A), (0, 19, 76, 5, 0x1F1A15),
        (9, 1, 1, 1, 0xF0E4CC), (66, 2, 1, 1, 0xF0E4CC),
        (58, 10, 4, 1, 0xF6D58A), (57, 11, 6, 4, 0xF6D58A), (58, 15, 4, 1, 0xF6D58A),
        (52, 14, 14, 1, 0x2B1F24), (49, 15, 22, 4, 0x2B1F24),
        (41, 9, 3, 11, 0x18140F), (45, 5, 3, 15, 0x18140F), (49, 3, 3, 17, 0x18140F), (53, 6, 3, 14, 0x18140F),
        (57, 10, 3, 10, 0x18140F),
        (42, 13, 1, 1, 0xC96A57), (46, 13, 1, 1, 0xC96A57), (50, 13, 1, 1, 0xC96A57), (54, 13, 1, 1, 0xC96A57),
        (58, 13, 1, 1, 0xC96A57),
        (40, 20, 21, 1, 0xF0E4CC),
    ]

    var body: some View {
        let s = Self.scale
        let (art, rows, wranglerX, wranglerY): ([Px], Int, Int, Int) = layout == .about
            ? (Self.about, 30, 18, 0) : (Self.welcome, 24, 20, -6)
        Canvas(rendersAsynchronously: false) { context, _ in
            for px in art {
                context.fill(Path(CGRect(x: CGFloat(px.x) * s, y: CGFloat(px.y) * s, width: CGFloat(px.w) * s, height: CGFloat(px.h) * s)),
                             with: .color(Color(hex: px.color)))
            }
            // The Wrangler, busking.
            for (y, row) in WranglerArt.rows(.busk).enumerated() where y + wranglerY >= 0 {
                for (x, key) in row.enumerated() {
                    guard let hex = WranglerArt.palette[key] else { continue }
                    context.fill(Path(CGRect(x: CGFloat(wranglerX + x) * s, y: CGFloat(wranglerY + y) * s, width: s, height: s)),
                                 with: .color(Color(hex: hex)))
                }
            }
        }
        .frame(width: Self.size.width, height: CGFloat(rows) * s)
        .accessibilityElement()
        .accessibilityLabel("The Wrangler busking beside the organ pipes at sundown")
    }
}
