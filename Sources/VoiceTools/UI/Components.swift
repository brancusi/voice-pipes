import AppKit
import CoreText
import SwiftUI

// Shared pieces of the design system (README → components): cards, check codes, the segmented control, fields,
// checkboxes, filter chips and the pixel headline. Screens build from these instead of restyling system controls.

extension VPFont {
    /// Silkscreen, the pixel face, for flavour headlines only (empty states, training success), always lowercase.
    /// Falls back to SF Mono bold if the bundled font isn't available.
    static func pixel(_ size: CGFloat) -> Font {
        NSFont(name: "Silkscreen-Regular", size: size).map { Font($0 as CTFont) }
            ?? .system(size: size, weight: .bold, design: .monospaced)
    }

    /// Registers the fonts shipped in Contents/Resources/Fonts for this process.
    static func registerBundledFonts(in directory: URL? = Bundle.main.resourceURL?.appendingPathComponent("Fonts")) {
        guard let directory,
              let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else { return }
        for url in files where url.pathExtension.lowercased() == "ttf" {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

/// A flavour headline in the pixel face: "quiet on the range". Never for anything someone must read to work.
struct PixelHeadline: View {
    let text: String
    var size: CGFloat = 22
    init(_ text: String, size: CGFloat = 22) { self.text = text; self.size = size }

    var body: some View {
        // The window's monospaced design would otherwise replace the pixel face.
        Text(text.lowercased()).font(VPFont.pixel(size)).fontDesign(nil).foregroundStyle(Palette.fg)
    }
}

/// A bg-200 card whose rows stack edge to edge.
struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .vpCard()
    }
}

/// A 1px `line` divider between rows.
struct Hairline: View {
    var body: some View { Rectangle().fill(Palette.line).frame(height: 1) }
}

/// `OK`, `INFO`, `WARN`, `FAIL` in the level's colour, in a fixed-width column.
struct StatusCode: View {
    let level: Check.Level
    var width: CGFloat? = 40

    var body: some View {
        Text(SetupView.code(level)).font(VPFont.label).tracking(0.9)
            .foregroundStyle(MenuView.color(level)).frame(width: width, alignment: .leading)
    }
}

/// A section: an UPPERCASE label over its content, 6px apart.
struct VPSection<Content: View, Accessory: View>: View {
    let title: String
    @ViewBuilder let accessory: Accessory
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder accessory: () -> Accessory = { EmptyView() }, @ViewBuilder content: () -> Content) {
        self.title = title
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                SectionLabel(title)
                accessory
                Spacer(minLength: 0)
            }
            content
        }
    }
}

/// The 2px rose focus ring, 2px outside the control.
private struct FocusRing: ViewModifier {
    let focused: Bool
    var radius: CGFloat = 4

    func body(content: Content) -> some View {
        content.overlay(
            RoundedRectangle(cornerRadius: radius + 2).stroke(Palette.pink, lineWidth: 2).padding(-3).opacity(focused ? 1 : 0)
        )
    }
}

extension View {
    func vpFocusRing(_ focused: Bool, radius: CGFloat = 4) -> some View { modifier(FocusRing(focused: focused, radius: radius)) }
}

/// A segmented choice: options on a mesquite track, the chosen one filled lavender. Works with the keyboard
/// (each option is a button) and reads as a radio group to VoiceOver.
struct VPSegmented<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(Value, String)]
    var fill = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let on = option.0 == selection
                Button { selection = option.0 } label: {
                    Text(option.1)
                        .font(.system(size: 12, weight: on ? .semibold : .regular, design: .monospaced))
                        .foregroundStyle(on ? Palette.onAccent : Palette.fgMuted)
                        .lineLimit(1)
                        .padding(.horizontal, 10).frame(height: 22)
                        .frame(maxWidth: fill ? .infinity : nil)
                        .background(RoundedRectangle(cornerRadius: 2).fill(on ? Palette.purple : .clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 4).fill(Palette.bg000))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.line, lineWidth: 1))
        .fixedSize(horizontal: !fill, vertical: true)
        .accessibilityElement(children: .contain)
    }
}

/// A field: an inset terminal (mesquite ground, `line` border, 4px corners) with the rose focus ring.
struct VPTextField: View {
    let prompt: String
    @Binding var text: String
    var axis: Axis = .horizontal
    var font: Font = VPFont.body
    var color: Color = Palette.fg
    var minHeight: CGFloat = 28
    var onSubmit: () -> Void = {}
    private var focusKey: String?
    @FocusState private var focused: Bool

    /// Names the field for `vp open … --field`.
    func focusKey(_ key: String) -> Self { var copy = self; copy.focusKey = key; return copy }

    init(_ prompt: String, text: Binding<String>, axis: Axis = .horizontal, font: Font = VPFont.body,
         color: Color = Palette.fg, minHeight: CGFloat = 28, onSubmit: @escaping () -> Void = {}) {
        self.prompt = prompt
        _text = text
        self.axis = axis
        self.font = font
        self.color = color
        self.minHeight = minHeight
        self.onSubmit = onSubmit
    }

    var body: some View {
        ZStack(alignment: axis == .vertical ? .topLeading : .leading) {
            // Our own placeholder: a TextField prompt's colour isn't honoured, and it must read as muted.
            if text.isEmpty {
                Text(prompt).font(font).foregroundStyle(Palette.fgMuted).lineLimit(1).allowsHitTesting(false)
            }
            TextField("", text: $text, axis: axis)
                .labelsHidden()
                .textFieldStyle(.plain)
                .font(font)
                .foregroundStyle(color)
                .focused($focused)
                .onSubmit(onSubmit)
                .accessibilityLabel(prompt)
        }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .frame(minHeight: minHeight, alignment: axis == .vertical ? .topLeading : .leading)
            // A click anywhere in the box (below the text, in the padding) focuses it; behind the field, so it
            // never takes clicks from the text itself.
            .background(Color.clear.contentShape(Rectangle()).onTapGesture { focused = true })
            .background(RoundedRectangle(cornerRadius: 4).fill(Palette.bg000))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.line, lineWidth: 1))
            .vpFocusRing(focused)
            .modifier(FocusKeyModifier(key: focusKey, focused: $focused))
    }
}

/// A multi-line editor for prompts (Return adds a line), styled as a field; grows with its text.
struct VPTextEditor: View {
    @Binding var text: String
    var minHeight: CGFloat = 64
    private var focusKey: String?
    @FocusState private var focused: Bool

    init(text: Binding<String>, minHeight: CGFloat = 64) {
        _text = text
        self.minHeight = minHeight
    }

    func focusKey(_ key: String) -> Self { var copy = self; copy.focusKey = key; return copy }

    var body: some View {
        TextEditor(text: $text)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(Palette.fg)
            .scrollContentBackground(.hidden)
            .scrollDisabled(true)
            .focused($focused)
            .padding(.horizontal, 3).padding(.vertical, 5)
            .frame(minHeight: minHeight)
            .fixedSize(horizontal: false, vertical: true)
            .background(RoundedRectangle(cornerRadius: 4).fill(Palette.bg000))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.line, lineWidth: 1))
            .vpFocusRing(focused)
            .modifier(FocusKeyModifier(key: focusKey, focused: $focused))
    }
}

/// The checkbox square on its own (for rows that are themselves the button).
struct CheckboxMark: View {
    let isOn: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2).fill(isOn ? Palette.purple : Palette.bg000)
            RoundedRectangle(cornerRadius: 2).strokeBorder(isOn ? Palette.purple : Palette.line, lineWidth: 1)
            if isOn { Text("✓").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(Palette.onAccent) }
        }
        .frame(width: 16, height: 16)
    }
}

/// A square checkbox: lavender with a ✓ when ticked, an empty field when not.
struct VPCheckbox: View {
    @Binding var isOn: Bool
    var label: String = ""

    var body: some View {
        Button { isOn.toggle() } label: {
            CheckboxMark(isOn: isOn).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

/// A filter chip; the selected one is filled lavender.
struct VPChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(selected ? .system(size: 12, weight: .semibold, design: .monospaced) : .system(size: 12, design: .monospaced))
                .foregroundStyle(selected ? Palette.onAccent : Palette.fgMuted)
                .lineLimit(1)
                .padding(.horizontal, 8).frame(height: 22)
                .background(RoundedRectangle(cornerRadius: 2).fill(selected ? Palette.purple : Palette.bg000))
                .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(selected ? Palette.purple : Palette.line, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// The wordmark: `voice | pipes`, lowercase, one weight, the pipe in sunset rose.
struct Wordmark: View {
    var size: CGFloat = 15
    var weight: Font.Weight = .semibold

    var body: some View {
        (Text("voice ") + Text("|").foregroundColor(Palette.pink) + Text(" pipes"))
            .font(.system(size: size, weight: weight, design: .monospaced))
            .foregroundStyle(Palette.fg)
            .accessibilityLabel("Voice Pipes")
    }
}

extension Date {
    /// Compact and log-like: "7 s ago", "2 min ago", "3 h ago", then "Oct 2, 09:41".
    var shortAgo: String {
        let seconds = max(0, Int(Date().timeIntervalSince(self)))
        switch seconds {
        case ..<60: return "\(seconds) s ago"
        case ..<3600: return "\(seconds / 60) min ago"
        case ..<86_400: return "\(seconds / 3600) h ago"
        default: return formatted(.dateTime.month(.abbreviated).day().hour().minute())
        }
    }
}

extension Int {
    /// Milliseconds with a thousands separator: "1,840 ms".
    var msLabel: String { "\(formatted(.number)) ms" }
}

extension Palette {
    /// The track colours offered in the editor: the sky accents (red rock is left out; it means recording).
    static let trackSwatches: [(name: String, hex: String)] = [
        ("Apricot", "#F0A35E"), ("Dusk blue", "#8FB8D6"), ("Cloud lavender", "#C3A3D4"),
        ("Sage", "#A9BF8A"), ("Marigold", "#E8C26A"), ("Sunset rose", "#EC8F7C"),
    ]

    /// A track's colour. Palette colours (stored as their Sundown hex) follow the theme, so they switch to their
    /// Daylight versions in light mode; any other colour is shown as stored.
    static func track(_ hex: String) -> Color {
        switch hex.uppercased() {
        case "#F0A35E": orange
        case "#8FB8D6": cyan
        case "#C3A3D4": purple
        case "#A9BF8A": green
        case "#E8C26A": yellow
        case "#EC8F7C": pink
        case "#E0694A": red
        default: Color(hex: hex)
        }
    }
}

/// An empty page: the Wrangler, a flavour headline in the pixel face, then a plain sentence that says what to do,
/// and the buttons that do it. The headline can tip its hat; the sentence gets to the point.
struct WranglerEmptyState: View {
    let headline: String
    var pose: WranglerArt.Pose = .busk
    var scale = 6
    let message: String
    var action: (String, () -> Void)?
    var secondary: (String, () -> Void)?

    init(headline: String, pose: WranglerArt.Pose = .busk, scale: Int = 6, message: String,
         action: (String, () -> Void)? = nil, secondary: (String, () -> Void)? = nil) {
        self.headline = headline
        self.pose = pose
        self.scale = scale
        self.message = message
        self.action = action
        self.secondary = secondary
    }

    var body: some View {
        VStack(spacing: 16) {
            Wrangler(pose: pose, scale: scale)
            PixelHeadline(headline)
            // No vertical fixedSize here: measured at its narrowest it would demand a tall window and stop the
            // window shrinking to its tile (the window's minimum size comes from its content).
            Text(message)
                .font(VPFont.body).lineSpacing(4).foregroundStyle(Palette.fgMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            if action != nil || secondary != nil {
                HStack(spacing: 10) {
                    if let action { Button(action.0, action: action.1).buttonStyle(.vpPrimary) }
                    if let secondary { Button(secondary.0, action: secondary.1).buttonStyle(.vpSecondary) }
                }
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A model's download: a thin bar that only moves forward, with "212 / 483 MB · 11 MB/s" (or "preparing for this
/// Mac…" while it compiles). Same height from start to finish, so the row never jumps.
struct ModelLoadBar: View {
    let status: ModelDownloads.Status?

    var body: some View {
        let fraction = status?.fraction ?? 0
        let preparing = status?.preparing ?? false
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(Palette.bg300)
                    RoundedRectangle(cornerRadius: 2).fill(preparing ? Palette.purple : Palette.cyan)
                        .frame(width: max(4, geo.size.width * fraction))
                        .animation(.linear(duration: 0.3), value: fraction)
                }
            }
            .frame(height: 4)
            Text(status?.label ?? "starting…")
                .font(.system(size: 11, design: .monospaced)).monospacedDigit()
                .foregroundStyle(Palette.fgMuted).lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(preparing ? "Preparing" : "Downloading")
        .accessibilityValue("\(Int(fraction * 100)) percent")
    }
}

/// Lays its children left to right and wraps onto as many lines as it needs (chips, tags).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += line + spacing; line = 0 }
            x += size.width + spacing
            line = max(line, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, width), height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += line + spacing; line = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            line = max(line, size.height)
        }
    }
}

/// An orange outlined tag for something a key is missing for ("NEEDS OPENROUTER KEY"), as in the block picker.
struct KeyTag: View {
    let text: String

    var body: some View {
        Text(text).font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(0.6)
            .foregroundStyle(Palette.orange)
            .lineLimit(1).fixedSize()
            .padding(.horizontal, 5).padding(.vertical, 1)
            .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Palette.orange, lineWidth: 1))
    }
}

extension Track {
    /// Any of its blocks runs on OpenRouter.
    var usesOpenRouter: Bool { allSteps.contains { $0.kind.usesOpenRouter } }
}

/// The on/off switch in the palette (the system one is grey and white): on, a purple track with an on-accent knob;
/// off, a bg300 track with a line border and a muted knob. VoiceOver still sees a switch.
struct VPSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        let on = configuration.isOn
        return Button { configuration.isOn.toggle() } label: {
            ZStack(alignment: on ? .trailing : .leading) {
                // .circular: the default continuous capsule draws its ends flattened at this size.
                Capsule(style: .circular).fill(on ? Palette.purple : Palette.bg300)
                    .overlay(Capsule(style: .circular).strokeBorder(on ? Color.clear : Palette.line, lineWidth: 1))
                Circle().fill(on ? Palette.onAccent : Palette.fgMuted).padding(3)
            }
            .frame(width: 34, height: 20)
            .animation(.easeOut(duration: 0.12), value: on)
            .contentShape(Capsule(style: .circular))
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }
}

extension ToggleStyle where Self == VPSwitchStyle {
    static var vpSwitch: VPSwitchStyle { VPSwitchStyle() }
}
