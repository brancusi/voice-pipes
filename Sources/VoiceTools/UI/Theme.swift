import AppKit
import SwiftUI

/// The Voice Pipes design system (Dracula / Alucard, one monospace face). Every colour and type style the UI uses
/// comes from here; the values match the design system's tokens.json.
enum Palette {
    // Grounds, deepest to highest.
    static let bg000 = dynamic(dark: 0x191A21, light: 0xF5F1DE)   // menu bar panel, sidebar
    static let bg100 = dynamic(dark: 0x21222C, light: 0xFFFBEB)   // window
    static let bg200 = dynamic(dark: 0x282A36, light: 0xFFFDF5)   // cards, lists
    static let bg300 = dynamic(dark: 0x343746, light: 0xEFEBD7)   // hover, fields, buttons
    static let line = dynamic(dark: 0x44475A, light: 0xCFCFDE)    // hairlines, selection

    // Text.
    static let fg = dynamic(dark: 0xF8F8F2, light: 0x1F1F1F)
    static let fgMuted = dynamic(dark: 0xA7ABBE, light: 0x57534A)
    /// Marks only in the dark theme (separators, handles, disabled icons): too faint for text there.
    static let comment = dynamic(dark: 0x6272A4, light: 0x6C664B)

    // Accents and states.
    static let purple = dynamic(dark: 0xBD93F9, light: 0x644AC9)  // accent, Transform, READ
    static let pink = dynamic(dark: 0xFF79C6, light: 0xA3144D)    // focus, keyboard
    static let cyan = dynamic(dark: 0x8BE9FD, light: 0x036A96)    // Transcribe, INFO
    static let green = dynamic(dark: 0x50FA7B, light: 0x14710A)   // Output, OK
    static let yellow = dynamic(dark: 0xF1FA8C, light: 0x846E15)  // PROC
    static let orange = dynamic(dark: 0xFFB86C, light: 0xA34D14)  // WARN, ERR
    static let red = dynamic(dark: 0xFF5555, light: 0xCB3A2A)     // REC, destructive
    static let onAccent = dynamic(dark: 0x191A21, light: 0xFFFFFF)

    // The HUD floats over any app, so it stays dark in both themes.
    static let hudBG = Color(hex: 0x191A21).opacity(0.9)
    static let hudFG = Color(hex: 0xF8F8F2)
    static let hudMuted = Color(hex: 0xA7ABBE)

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

/// A keycap for a hotkey.
struct Keycap: View {
    let text: String
    var mode: String?

    var body: some View {
        HStack(spacing: 4) {
            Text(text).foregroundStyle(Palette.fgMuted)
            if let mode { Text(mode).foregroundStyle(Palette.comment) }
        }
        .font(VPFont.caption)
        .padding(.horizontal, 5).frame(height: 18)
        .background(RoundedRectangle(cornerRadius: 2).fill(Palette.bg300))
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
