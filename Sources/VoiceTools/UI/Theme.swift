import AppKit
import SwiftUI

/// The Voice Pipes design system (Sundown / Daylight, one monospace face). Every colour and type style the UI uses
/// comes from here; the values match the design system's tokens.json. Names follow the hue family
/// (purple = cloud lavender, cyan = dusk blue, green = sage, …) so they read the same as the tokens.
enum Palette {
    // Grounds, deepest to highest: desert earth.
    static let bg000 = dynamic(dark: 0x18140F, light: 0xEFE3CC)   // mesquite: menu bar panel, sidebar
    static let bg100 = dynamic(dark: 0x1F1A15, light: 0xF7EEDC)   // umber: window
    static let bg200 = dynamic(dark: 0x27211B, light: 0xFBF5E8)   // saddle: cards, lists
    static let bg300 = dynamic(dark: 0x332B24, light: 0xEADCC2)   // leather: hover, fields, buttons
    static let line = dynamic(dark: 0x4A3F35, light: 0xD3C2A3)    // fence: hairlines, selection

    // Text.
    static let fg = dynamic(dark: 0xF0E4CC, light: 0x2A211B)      // bone / ink
    static let fgMuted = dynamic(dark: 0xB8A88E, light: 0x5E5144) // sagebrush
    /// Dust: marks only (separators, handles, disabled icons), too faint for text.
    static let comment = dynamic(dark: 0x7D6D5C, light: 0x7A6A57)

    // Accents and states: the sundown sky.
    static let purple = dynamic(dark: 0xC3A3D4, light: 0x6C4A86)  // cloud lavender: accent, Transform, READ
    static let pink = dynamic(dark: 0xEC8F7C, light: 0xA3432E)    // sunset rose: focus, keyboard
    static let cyan = dynamic(dark: 0x8FB8D6, light: 0x2C5F80)    // dusk blue: Transcribe, INFO
    static let green = dynamic(dark: 0xA9BF8A, light: 0x46632F)   // sage: Output, OK
    static let yellow = dynamic(dark: 0xE8C26A, light: 0x7A5C0E)  // marigold: PROC
    static let orange = dynamic(dark: 0xF0A35E, light: 0x93501A)  // apricot: WARN, ERR
    static let red = dynamic(dark: 0xE0694A, light: 0xA1341B)     // red rock: REC, destructive
    static let onAccent = dynamic(dark: 0x18140F, light: 0xFFFFFF)

    // The HUD floats over any app, so it stays dark in both themes.
    static let hudBG = Color(hex: 0x18140F).opacity(0.9)
    static let hudFG = Color(hex: 0xF0E4CC)
    static let hudMuted = Color(hex: 0xB8A88E)

    private static func dynamic(dark: UInt32, light: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

/// The type scale: one monospace family (SF Mono), hierarchy by size, weight and colour.
enum VPFont {
    static let display = Font.system(size: 20, weight: .semibold, design: .monospaced)
    static let title = Font.system(size: 15, weight: .semibold, design: .monospaced)
    static let body = Font.system(size: 13, design: .monospaced)
    static let bodyStrong = Font.system(size: 13, weight: .semibold, design: .monospaced)
    static let label = Font.system(size: 11, weight: .semibold, design: .monospaced)
    static let caption = Font.system(size: 11, design: .monospaced)
    static let micro = Font.system(size: 10, design: .monospaced)
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// An UPPERCASE section header ("TRACKS", "HISTORY").
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased()).font(VPFont.label).tracking(0.9).foregroundStyle(Palette.fgMuted)
    }
}

/// A keycap for a hotkey: SF Mono 12 bold in bone on leather with a hairline, 22 tall. `small` is for a hotkey
/// mentioned inside a sentence.
struct Keycap: View {
    let text: String
    var mode: String?
    var small = false

    var body: some View {
        HStack(spacing: 4) {
            Text(text).foregroundStyle(small ? Palette.fgMuted : Palette.fg)
            if let mode { Text(mode).fontWeight(.regular).foregroundStyle(Palette.comment) }
        }
        .font(.system(size: small ? 11 : 12, weight: small ? .regular : .bold, design: .monospaced))
        .tracking(small ? 0 : 0.7)
        .padding(.horizontal, small ? 5 : 8).frame(height: small ? 18 : 22)
        .background(RoundedRectangle(cornerRadius: 2).fill(Palette.bg300))
        .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(small ? .clear : Palette.line, lineWidth: 1))
        .fixedSize()
    }
}

/// The one-colour Voice Pipes mark for app chrome (the panel header): the › prompt, three pipes with their slits,
/// and the base pipe, on an 18 × 18 grid, in bone on Sundown and ink on Daylight. The full-colour sundown mark is
/// for the app icon, About and marketing only.
struct MonoMark: View {
    var scale: CGFloat = 2

    private static let pixels: [(Int, Int, Int, Int)] = {
        var rects: [(Int, Int, Int, Int)] = [(1, 11, 1, 1), (2, 12, 1, 1), (3, 13, 1, 1), (2, 14, 1, 1), (1, 15, 1, 1)]
        // Pipes: x, top row, 3 wide down to row 13, with a 1-px slit at row 10 in the middle column.
        for (x, top) in [(6, 7), (10, 3), (14, 6)] {
            rects.append((x, top, 3, 10 - top))           // above the slit
            rects.append((x, 10, 1, 1))
            rects.append((x + 2, 10, 1, 1))               // either side of the slit
            rects.append((x, 11, 3, 3))                   // rows 11–13
        }
        rects.append((5, 15, 13, 1))                      // the base pipe
        return rects
    }()

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, _ in
            for (x, y, w, h) in Self.pixels {
                context.fill(Path(CGRect(x: CGFloat(x) * scale, y: CGFloat(y) * scale, width: CGFloat(w) * scale, height: CGFloat(h) * scale)),
                             with: .color(Palette.fg))
            }
        }
        .frame(width: 18 * scale, height: 18 * scale)
        .accessibilityHidden(true)
    }
}

/// Buttons: primary (one per view), secondary, ghost (inline adds), danger (destructive).
struct VPButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, ghost, danger }
    var kind: Kind = .secondary
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(VPFont.bodyStrong)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, kind == .ghost ? 8 : 12)
            .frame(height: 26)
            .foregroundStyle(foreground)
            .background(RoundedRectangle(cornerRadius: 4).fill(background(pressed: configuration.isPressed)))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(border, lineWidth: 1))
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.4)
    }

    private var foreground: Color {
        switch kind {
        case .primary: Palette.onAccent
        case .secondary: Palette.fg
        case .ghost: Palette.purple
        case .danger: Palette.red
        }
    }

    private func background(pressed: Bool) -> Color {
        switch kind {
        case .primary: pressed ? Palette.pink : Palette.purple
        case .secondary: pressed ? Palette.line : Palette.bg300
        case .ghost, .danger: pressed ? Palette.bg300 : .clear
        }
    }

    private var border: Color {
        switch kind {
        case .secondary: Palette.line
        case .danger: Palette.red
        default: .clear
        }
    }
}

extension ButtonStyle where Self == VPButtonStyle {
    static var vpPrimary: VPButtonStyle { VPButtonStyle(kind: .primary) }
    static var vpSecondary: VPButtonStyle { VPButtonStyle(kind: .secondary) }
    static var vpGhost: VPButtonStyle { VPButtonStyle(kind: .ghost) }
    static var vpDanger: VPButtonStyle { VPButtonStyle(kind: .danger) }
}

/// A small icon-only button (copy, chevrons, delete).
struct VPIconButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12))
            .frame(width: 26, height: 24)
            .foregroundStyle(hovering || configuration.isPressed ? Palette.fg : Palette.fgMuted)
            .background(RoundedRectangle(cornerRadius: 4).fill(hovering || configuration.isPressed ? Palette.bg300 : .clear))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}

extension ButtonStyle where Self == VPIconButtonStyle {
    static var vpIcon: VPIconButtonStyle { VPIconButtonStyle() }
}

extension View {
    /// Cards and grouped lists: bg-200 with a hairline, radius-md.
    func vpCard() -> some View {
        background(RoundedRectangle(cornerRadius: 6).fill(Palette.bg200))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.line, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    /// The whole-window treatment: the mono face, the purple accent, the window ground.
    func vpWindow() -> some View {
        fontDesign(.monospaced)
            .font(VPFont.body)
            .tint(Palette.purple)
            .foregroundStyle(Palette.fg)
    }
}

extension StepKind {
    /// Pipeline colours: Input muted, Transcribe cyan, Transform purple, Output green.
    var tint: Color {
        switch category {
        case "Input": Palette.fgMuted
        case "Transcribe": Palette.cyan
        case "Output": Palette.green
        default: Palette.purple
        }
    }
}

/// Light, dark or follow the Mac. Applied app-wide (windows and the menu bar panel); the HUD stays dark regardless.
enum AppearanceChoice: String, CaseIterable, Identifiable {
    case auto, daylight, sundown

    static let defaultsKey = "appearance"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: "Auto"
        case .daylight: "Daylight"
        case .sundown: "Sundown"
        }
    }

    var detail: String {
        switch self {
        case .auto: "Follows your Mac: Daylight by day, Sundown when macOS is dark."
        case .daylight: "Always light: bone paper and ink."
        case .sundown: "Always dark: desert earth and sunset accents."
        }
    }

    private var appearance: NSAppearance? {
        switch self {
        case .auto: nil
        case .daylight: NSAppearance(named: .aqua)
        case .sundown: NSAppearance(named: .darkAqua)
        }
    }

    static var current: AppearanceChoice {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(AppearanceChoice.init) ?? .auto
    }

    @MainActor static func apply(_ choice: AppearanceChoice = current) {
        NSApp.appearance = choice.appearance
    }
}
