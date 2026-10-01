import AVFoundation
import SwiftUI

struct TrackDetailView: View {
    let app: AppState
    @Binding var track: Track
    let onDelete: () -> Void
    @State private var expandedStep: Step.ID?

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $track.name).font(.title2.weight(.semibold))
                Toggle("Enabled", isOn: $track.enabled)
                ColorPicker("Color", selection: colorBinding, supportsOpacity: false)
            }

            Section("Triggers") {
                ForEach($track.triggers) { $trigger in
                    HStack(spacing: 12) {
                        KeyRecorder(combo: $trigger.combo, app: app)
                        Picker("Mode", selection: $trigger.mode) {
                            Text("Toggle").tag(Trigger.Mode.toggle)
                            Text("Press & hold").tag(Trigger.Mode.hold)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 200)
                        if app.store.conflicts.contains(trigger.combo) {
                            Label("Also used by another trigger", systemImage: "exclamationmark.triangle")
                                .font(.caption).foregroundStyle(.orange)
                        } else if app.unavailableCombos.contains(trigger.combo) {
                            Label("Taken by another app", systemImage: "exclamationmark.triangle")
                                .font(.caption).foregroundStyle(.orange)
                        }
                        Spacer()
                        Button { track.triggers.removeAll { $0.id == trigger.id } } label: { Image(systemName: "xmark") }
                            .buttonStyle(.borderless)
                    }
                }
                Button("+ Add trigger") {
                    track.triggers.append(Trigger(combo: KeyCombo(key: .n, modifiers: [.control, .option]), mode: .toggle))
                }
                .buttonStyle(.borderless)
            }

            Section {
                ForEach($track.steps) { $step in
                    StepRow(step: $step, speaker: app.speaker, expanded: expandedStep == step.id) {
                        expandedStep = expandedStep == step.id ? nil : step.id
                    } onDelete: {
                        track.steps.removeAll { $0.id == step.id }
                    }
                }
                .onMove { track.steps.move(fromOffsets: $0, toOffset: $1) }
                addStepMenu
            } header: {
                Text("Pipeline")
            } footer: {
                if let error = track.validationError {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
            }

            Section {
                HStack {
                    Button("Run now") { app.start(track) }
                    Spacer()
                    Button("Delete track", role: .destructive, action: onDelete)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var addStepMenu: some View {
        Menu("+ Add step") {
            ForEach(["Input", "Transcribe", "Transform", "Output"], id: \.self) { category in
                Section(category) {
                    ForEach(StepKind.catalog.filter { $0.category == category }, id: \.self) { kind in
                        Button("\(kind.title)   \(kind.input.rawValue) → \(kind.output.rawValue)") {
                            let step = Step(kind: kind)
                            track.steps.append(step)
                            expandedStep = step.id
                        }
                    }
                }
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var colorBinding: Binding<Color> {
        Binding {
            Color(hex: track.colorHex)
        } set: { color in
            let c = NSColor(color).usingColorSpace(.sRGB) ?? .systemBlue
            track.colorHex = String(format: "#%02X%02X%02X", Int(c.redComponent * 255),
                                    Int(c.greenComponent * 255), Int(c.blueComponent * 255))
        }
    }
}

private struct StepRow: View {
    @Binding var step: Step
    let speaker: Speaker
    let expanded: Bool
    let onToggle: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 7).fill(step.kind.tint.opacity(0.15)))
                    .foregroundStyle(step.kind.tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(step.kind.category.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    Text(step.kind.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                }
                Spacer()
                Text("\(step.kind.input.rawValue) → \(step.kind.output.rawValue)")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                Button(action: onToggle) { Image(systemName: expanded ? "chevron.up" : "chevron.down") }
                    .buttonStyle(.borderless)
                Button(action: onDelete) { Image(systemName: "trash") }.buttonStyle(.borderless)
            }
            if expanded {
                StepConfigView(kind: $step.kind, speaker: speaker).padding(.leading, 40)
            }
        }
        .padding(.vertical, 2)
    }

    private var icon: String {
        switch step.kind {
        case .microphone: "mic"
        case .text: "text.cursor"
        case .parakeet: "bolt"
        case .openRouterSTT: "waveform"
        case .llm: "sparkles"
        case .http: "network"
        case .template: "curlybraces"
        case .paste: "doc.on.clipboard"
        case .copy: "doc.on.doc"
        case .speak, .openRouterSpeech: "speaker.wave.2"
        case .showHUD: "rectangle.bottomthird.inset.filled"
        }
    }
}

/// Edits the associated values of a step kind in place.
private struct StepConfigView: View {
    @Binding var kind: StepKind
    let speaker: Speaker

    var body: some View {
        switch kind {
        case .microphone:
            Text("Default input device · 16 kHz mono").font(.caption).foregroundStyle(.secondary)

        case .text(let sources):
            VStack(alignment: .leading, spacing: 4) {
                Text("Uses the first source that has text:").font(.caption).foregroundStyle(.secondary)
                ForEach(TextSource.allCases) { source in
                    Toggle(source.label, isOn: Binding {
                        sources.contains(source)
                    } set: { on in
                        var updated = sources.filter { $0 != source }
                        if on { updated.append(source) }
                        kind = .text(sources: TextSource.allCases.filter(updated.contains))
                    })
                }
            }

        case .parakeet(let pauseMs, let storedMode):
            let mode = storedMode ?? .onRelease
            Picker("Mode", selection: Binding { mode } set: { kind = .parakeet(chunkOnPauseMs: pauseMs, mode: $0) }) {
                ForEach(ParakeetMode.allCases) { Text($0.label).tag($0) }
            }
            Text(mode.detail).font(.caption).foregroundStyle(.secondary)
            if mode == .pauseChunks {
                HStack {
                    Text("Cut at pauses longer than")
                    Slider(value: Binding { Double(pauseMs) } set: { kind = .parakeet(chunkOnPauseMs: Int($0), mode: mode) },
                           in: 300...1200, step: 50)
                    Text("\(pauseMs) ms").monospacedDigit().frame(width: 60, alignment: .trailing)
                }
            }
            if mode != .onRelease {
                Text("Chunking and streaming apply when this step directly follows Microphone.")
                    .font(.caption).foregroundStyle(.secondary)
            }

        case .openRouterSTT(let model):
            LabeledContent("Model") {
                ModelPicker(capability: .transcription, modelID: Binding { model } set: { kind = .openRouterSTT(model: $0) })
            }

        case .llm(let model, let prompt, let policy):
            LabeledContent("Model") {
                ModelPicker(capability: .text, modelID: Binding { model } set: { kind = .llm(model: $0, prompt: prompt, onFailure: policy) })
            }
            Picker("If this step fails", selection: Binding { policy } set: { kind = .llm(model: model, prompt: prompt, onFailure: $0) }) {
                Text("Pass input through").tag(FailurePolicy.passThrough)
                Text("Stop the track").tag(FailurePolicy.stop)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Instructions. Use {{input}} to place the text; otherwise it's sent as the user message.")
                    .font(.caption).foregroundStyle(.secondary)
                TextEditor(text: Binding { prompt } set: { kind = .llm(model: model, prompt: $0, onFailure: policy) })
                    .font(.system(size: 12))
                    .frame(minHeight: 70)
            }

        case .http(let url, let method, let headers, let body, let field):
            let set = { (u: String, m: String, h: [String: String], b: String, f: String) in
                kind = .http(url: u, method: m, headers: h, bodyTemplate: b, responseField: f)
            }
            Picker("Method", selection: Binding { method } set: { set(url, $0, headers, body, field) }) {
                ForEach(["GET", "POST", "PUT", "PATCH"], id: \.self) { Text($0).tag($0) }
            }
            TextField("URL", text: Binding { url } set: { set($0, method, headers, body, field) })
            TextField("Headers (Name: value, one per line)", text: Binding {
                headers.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
            } set: { text in
                let parsed = text.split(separator: "\n").reduce(into: [String: String]()) { dict, line in
                    let parts = line.split(separator: ":", maxSplits: 1)
                    if parts.count == 2 { dict[parts[0].trimmingCharacters(in: .whitespaces)] = parts[1].trimmingCharacters(in: .whitespaces) }
                }
                set(url, method, parsed, body, field)
            }, axis: .vertical)
            TextField("Body ({{input}} or {{input_json}})", text: Binding { body } set: { set(url, method, headers, $0, field) },
                      axis: .vertical)
                .font(.system(.body, design: .monospaced))
            TextField("Response field (dotted path, empty = whole body)",
                      text: Binding { field } set: { set(url, method, headers, body, $0) })

        case .template(let template):
            TextField("Template ({{input}})", text: Binding { template } set: { kind = .template($0) }, axis: .vertical)

        case .paste(let restore):
            Toggle("Restore previous clipboard after pasting", isOn: Binding { restore } set: { kind = .paste(restoreClipboard: $0) })

        case .copy:
            Text("Leaves the text on the clipboard.").font(.caption).foregroundStyle(.secondary)

        case .speak(let voiceID, let rate):
            enginePicker
            Picker("Voice", selection: Binding { voiceID ?? "" } set: { kind = .speak(voiceID: $0.isEmpty ? nil : $0, rate: rate) }) {
                Text("System default (best installed)").tag("")
                ForEach(Self.voices, id: \.identifier) { voice in
                    Text("\(voice.name) · \(voice.quality == .premium ? "Premium" : voice.quality == .enhanced ? "Enhanced" : "Default")")
                        .tag(voice.identifier)
                }
            }
            HStack {
                Text("Speed")
                Slider(value: Binding { Double(rate) } set: { kind = .speak(voiceID: voiceID, rate: Float($0)) }, in: 0.6...2.0, step: 0.1)
                Text(String(format: "%.1f×", rate)).monospacedDigit().frame(width: 44, alignment: .trailing)
            }

        case .openRouterSpeech(let model, let voice, let rate):
            enginePicker
            LabeledContent("Model") {
                ModelPicker(capability: .speech, modelID: Binding { model } set: { _ in }) { picked in
                    // A new model has its own voices: keep the voice only if the new model offers it.
                    let keep = picked.voices.contains(voice) ? voice : picked.defaultVoice ?? ""
                    kind = .openRouterSpeech(model: picked.id, voice: keep, rate: rate)
                }
            }
            LabeledContent("Voice") {
                VoicePicker(modelID: model, voice: Binding { voice } set: { kind = .openRouterSpeech(model: model, voice: $0, rate: rate) },
                            speaker: speaker)
            }
            HStack {
                Text("Speed")
                Slider(value: Binding { Double(rate) } set: { kind = .openRouterSpeech(model: model, voice: voice, rate: Float($0)) },
                       in: 0.6...2.0, step: 0.1)
                Text(String(format: "%.1f×", rate)).monospacedDigit().frame(width: 44, alignment: .trailing)
            }
            Text("Long text is read in passages: the first starts within a second or two, the next downloads while you listen.")
                .font(.caption).foregroundStyle(.secondary)

        case .showHUD:
            Text("Shows the text in the HUD for a few seconds.").font(.caption).foregroundStyle(.secondary)
        }
    }

    /// Switches a Speak step between a macOS voice and an OpenRouter speech model, keeping its speed.
    private var enginePicker: some View {
        Picker("Engine", selection: Binding {
            if case .openRouterSpeech = kind { 1 } else { 0 }
        } set: { engine in
            let rate: Float = switch kind {
            case .speak(_, let r), .openRouterSpeech(_, _, let r): r
            default: 1
            }
            kind = engine == 1
                ? .openRouterSpeech(model: StepKind.defaultSpeechModel, voice: StepKind.defaultSpeechVoice, rate: rate)
                : .speak(voiceID: nil, rate: rate)
        }) {
            Text("macOS voice").tag(0)
            Text("OpenRouter").tag(1)
        }
        .pickerStyle(.segmented)
    }

    private static let voices: [AVSpeechSynthesisVoice] = {
        let language = AVSpeechSynthesisVoice.currentLanguageCode().prefix(2)
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(language) }
            .sorted { ($0.quality.rawValue, $0.name) > ($1.quality.rawValue, $1.name) }
    }()
}

/// Click, then press a key combination to record it.
private struct KeyRecorder: View {
    @Binding var combo: KeyCombo
    let app: AppState
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(recording ? "Press keys…" : combo.display) {
            recording ? stop() : start()
        }
        .frame(minWidth: 130)
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        app.hotkeysSuspended = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                stop() // plain Esc cancels
            } else {
                combo = KeyCombo(key: .init(code: UInt32(event.keyCode)), modifiers: .init(event.modifierFlags))
                stop()
            }
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
