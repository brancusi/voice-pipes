import AppKit
import SwiftUI

/// A track's hotkey shown large (each key its own cap), with Change… to record a new one and how it's played
/// (hold, toggle, once). Setup's "Try it" step: pick your dictation key without opening the track editor.
struct HotkeyPicker: View {
    let app: AppState
    let trackID: Track.ID
    @State private var recording = false
    @State private var monitor: Any?
    @State private var problem: String?

    private var index: Int? { app.store.tracks.firstIndex { $0.id == trackID } }
    private var trigger: Trigger? { index.flatMap { app.store.tracks[$0].triggers.first } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if recording {
                    Text("Press the keys you want…")
                        .font(.system(size: 18, weight: .semibold, design: .monospaced)).foregroundStyle(Palette.pink)
                        .padding(.horizontal, 16).frame(height: 48)
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.pink, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                } else if let trigger {
                    ForEach(Array(trigger.combo.parts.enumerated()), id: \.offset) { _, part in BigKeycap(text: part) }
                }
                Spacer(minLength: 12)
                Button(recording ? "Cancel" : "Change…") { recording ? stop() : start() }.buttonStyle(.vpSecondary)
            }
            if let trigger, let index {
                HStack(spacing: 12) {
                    VPSegmented(selection: Binding { trigger.mode } set: { app.store.tracks[index].triggers[0].mode = $0 },
                                options: [Trigger.Mode.hold, .toggle].map { ($0, $0.label) })
                    Text(warning(trigger.combo) ?? "").font(VPFont.caption).foregroundStyle(Palette.orange).lineLimit(1)
                }
            }
            if let problem {
                Text(problem).font(VPFont.caption).foregroundStyle(Palette.orange)
            }
        }
        .onDisappear(perform: stop)
    }

    private func warning(_ combo: KeyCombo) -> String? {
        if let other = app.store.clashes(for: trackID).first(where: { $0.combo == combo })?.track { return "also runs “\(other.name)”" }
        if app.unavailableCombos.contains(combo) { return "taken by another app: pick another" }
        return nil
    }

    private func start() {
        problem = nil
        recording = true
        app.hotkeysSuspended = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if event.keyCode == 53, flags.isEmpty { stop(); return nil }  // plain Esc cancels
            let combo = KeyCombo(key: .init(code: UInt32(event.keyCode)), modifiers: .init(event.modifierFlags))
            if combo.modifiers.isEmpty, !combo.isUsableAlone {
                problem = "Add ⌘, ⌥, ⌃ or ⇧ (or use an F key), so it doesn't take over your typing."
                return nil
            }
            if let index {
                if app.store.tracks[index].triggers.isEmpty {
                    app.store.tracks[index].triggers.append(Trigger(combo: combo, mode: .hold))
                } else {
                    app.store.tracks[index].triggers[0].combo = combo
                }
            }
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording { app.hotkeysSuspended = false }
        recording = false
    }
}

/// One key, large: what to press, readable at a glance.
struct BigKeycap: View {
    let text: String

    private static let names = ["⌃": "control", "⌥": "option", "⇧": "shift", "⌘": "command"]

    var body: some View {
        VStack(spacing: 1) {
            Text(text).font(.system(size: 24, weight: .bold, design: .monospaced)).foregroundStyle(Palette.fg)
            // A modifier's name under its symbol, as printed on Mac keyboards.
            if let name = Self.names[text] {
                Text(name).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(Palette.fgMuted)
            }
        }
            .padding(.horizontal, 12).frame(minWidth: 48, minHeight: 48)
            .background(RoundedRectangle(cornerRadius: 4).fill(Palette.bg300))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.line, lineWidth: 1))
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.line).frame(height: 3).padding(.horizontal, 1).padding(.bottom, 1) }
            .fixedSize()
    }
}
