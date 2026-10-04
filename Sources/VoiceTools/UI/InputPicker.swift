import SwiftUI

private struct AppInputKey: EnvironmentKey {
    static let defaultValue = AudioInputs.system
}

extension EnvironmentValues {
    /// The app's mic ([settings] input), for "App default (…)" in a track's Microphone block.
    var appInput: String {
        get { self[AppInputKey.self] }
        set { self[AppInputKey.self] = newValue }
    }
}

/// Picks a mic: the system's input or one by name. With `appDefault`, a first option "App default" (nil) follows
/// Setup → Microphone. A mic that's named but not connected stays listed (and records from the system's meanwhile).
struct InputPicker: View {
    @Binding var selection: String?
    /// The app's input; nil when this picker sets it (Setup).
    var appDefault: String?
    /// Re-read when the menu opens: mics come and go.
    @State private var devices = AudioInputs.all()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Input", selection: $selection) {
                if let appDefault {
                    Text("App default · \(AudioInputs.label(appDefault))").tag(String?.none)
                }
                Text(AudioInputs.label(AudioInputs.system)).tag(String?.some(AudioInputs.system))
                ForEach(devices, id: \.name) { device in
                    Text(device.name + (device.bluetooth ? " · Bluetooth" : "")).tag(String?.some(device.name))
                }
                if let selection, selection != AudioInputs.system, !devices.contains(where: { $0.name == selection }) {
                    Text("\(selection) (not connected)").tag(String?.some(selection))
                }
            }
            .labelsHidden().frame(maxWidth: 320)
            .onAppear { devices = AudioInputs.all() }
            .onHover { if $0 { devices = AudioInputs.all() } }
            if let note { Text(note).font(VPFont.caption).foregroundStyle(Palette.fgMuted).fixedSize(horizontal: false, vertical: true) }
        }
    }

    /// What's worth knowing about the mic this resolves to.
    private var note: String? {
        let input = selection ?? appDefault ?? AudioInputs.system
        if !AudioInputs.isConnected(input) { return "Not connected: records from \(AudioInputs.label(AudioInputs.system)) until it is." }
        if AudioInputs.resolve(input)?.bluetooth == true {
            return "Bluetooth: not kept ready (it would put the headset in call mode), so a take starts a moment after you press."
        }
        return nil
    }
}
