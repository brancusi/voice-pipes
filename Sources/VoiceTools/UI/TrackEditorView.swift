import AVFoundation
import SwiftUI

struct TrackDetailView: View {
    let app: AppState
    @Binding var track: Track
    let onDelete: () -> Void
    @State private var expandedStep: Step.ID?
    @State private var draggingStep: Step.ID?
    @State private var confirmingDelete = false
    @FocusState private var nameFocused: Bool

    init(app: AppState, track: Binding<Track>, expanded: Step.ID? = nil, onDelete: @escaping () -> Void) {
        self.app = app
        _track = track
        self.onDelete = onDelete
        _expandedStep = State(initialValue: expanded)
    }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                titleRow.id("title").vpFlash("title-\(track.id)")
                VPSection("Triggers") { triggers }.id("triggers").vpFlash("triggers-\(track.id)")
                VPSection("Pipeline", accessory: {
                    Text("drag ⋮⋮ to reorder").font(VPFont.caption).foregroundStyle(Palette.comment)
                }) { pipeline }.id("pipeline")
                VStack(spacing: 12) {
                    Hairline()
                    HStack(spacing: 10) {
                        Text("Saved").font(VPFont.caption).foregroundStyle(Palette.fgMuted)
                            .help("Changes save as you make them")
                        Spacer()
                        Button("Duplicate") { app.duplicateTrack(track.id) }.buttonStyle(.vpSecondary)
                            .help("A copy of this track, turned off, right below it (⌘D)")
                        Button("Delete track") { confirmingDelete = true }.buttonStyle(.vpDanger)
                    }
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 32).padding(.vertical, 24)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { takeRequest(proxy) }
        .onChange(of: UINav.shared.editor) { _, _ in takeRequest(proxy) }
        }
        .onAppear { report() }
        .onChange(of: expandedStep) { _, _ in report() }
        .onDisappear { UINav.shared.expandedStep = nil; UINav.shared.editingRoutes = [] }
        .background(Palette.bg100)
        .confirmationDialog("Delete “\(track.name)”?", isPresented: $confirmingDelete) {
            Button("Delete track", role: .destructive, action: onDelete)
        } message: {
            Text("Its hotkeys stop working. Its runs stay in History.")
        }
    }

    /// `vp open track <id> --step n --route n --section triggers|pipeline` (and outside edits): expand, scroll, flash.
    private func takeRequest(_ proxy: ScrollViewProxy) {
        guard let request = UINav.shared.editor, request.track == track.id else { return }
        UINav.shared.editor = nil
        var target = request.section
        var flash: String?
        if let n = request.step, track.steps.indices.contains(n - 1) {
            let step = track.steps[n - 1]
            if request.expand { expandedStep = step.id }
            target = "step-\(step.id)"
            flash = target
            if let r = request.route, let routes = step.kind.routes, routes.indices.contains(r - 1) {
                UINav.shared.openRoute = .init(step: step.id, index: r - 1)
                target = "route-\(routes[r - 1].id)"
                flash = target
            }
        } else if let section = request.section {
            flash = section == "triggers" ? "triggers-\(track.id)" : section == "title" ? "title-\(track.id)" : nil
        }
        guard let target else { return }
        // Once the expanded step has laid out.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(target, anchor: .center) }
            if let flash { UINav.shared.highlight(flash) }
        }
    }

    private func report() {
        UINav.shared.expandedStep = track.steps.firstIndex { $0.id == expandedStep }.map { $0 + 1 }
    }

    /// Colour, name, Enabled and Run now; under them, a missing OpenRouter key if this track needs one.
    private var titleRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            titleControls
            if track.usesOpenRouter, !app.hasOpenRouterKey {
                HStack(spacing: 10) {
                    KeyTag(text: "NEEDS OPENROUTER KEY")
                    Button("Add a key in Setup →") {
                        UINav.shared.setupSection = "connections"
                        app.mainSection = .setup
                    }
                    .buttonStyle(.plain).font(VPFont.caption).foregroundStyle(Palette.purple)
                }
            }
        }
    }

    private var titleControls: some View {
        HStack(spacing: 12) {
            TrackColorMenu(hex: $track.colorHex)
            TextField("", text: $track.name, prompt: Text("Track name").foregroundStyle(Palette.fgMuted))
                .labelsHidden()
                .textFieldStyle(.plain)
                .font(VPFont.display)
                .focused($nameFocused)
                .modifier(FocusKeyModifier(key: "name", focused: $nameFocused))
                .frame(minWidth: 40)
                // The name gives way first in a narrow window; the controls keep their size.
                .layoutPriority(-1)
            Spacer(minLength: 8)
            // The caption is dropped, never wrapped, when there's no room; the switch keeps its label for VoiceOver.
            ViewThatFits(in: .horizontal) {
                enabledCaption.fixedSize()
                Color.clear.frame(width: 0, height: 0)
            }
            enabledSwitch
            Button("▶ Run now") { app.start(track) }.buttonStyle(.vpPrimary)
        }
    }

    @ViewBuilder private func triggerWarning(_ combo: KeyCombo) -> some View {
        if let other = app.store.clashes(for: track.id).first(where: { $0.combo == combo })?.track {
            Text(track.enabled ? "WARN · also runs “\(other.name)”" : "also on “\(other.name)”: enabling asks")
                .font(VPFont.caption).foregroundStyle(track.enabled ? Palette.orange : Palette.fgMuted).lineLimit(1)
        } else if app.store.conflicts.contains(combo) {
            Text("WARN · also used by another trigger").font(VPFont.caption).foregroundStyle(Palette.orange).lineLimit(1)
        } else if app.unavailableCombos.contains(combo) {
            Text("WARN · taken by another app").font(VPFont.caption).foregroundStyle(Palette.orange).lineLimit(1)
        }
    }

    private var enabledCaption: some View {
        Text("Enabled").font(.system(size: 12, design: .monospaced)).foregroundStyle(Palette.fgMuted)
    }

    private var enabledSwitch: some View {
        Toggle("Enabled", isOn: Binding { track.enabled } set: { app.setEnabled(track.id, $0) })
            .labelsHidden().toggleStyle(.vpSwitch)
    }

    private var triggers: some View {
        Card {
            ForEach($track.triggers) { $trigger in
                if trigger.id != track.triggers.first?.id { Hairline() }
                let recorder = KeyRecorder(combo: $trigger.combo, app: app)
                let mode = VPSegmented(selection: $trigger.mode, options: Trigger.Mode.allCases.map { ($0, $0.label) })
                let remove = Button { track.triggers.removeAll { $0.id == trigger.id } } label: { Image(systemName: "xmark") }
                    .buttonStyle(.vpIcon).help("Remove this trigger")
                let warning = triggerWarning(trigger.combo)
                // One line when there's room; the mode switch goes under the key in a narrow window.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { recorder; mode; warning; Spacer(minLength: 0); remove }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) { recorder; Spacer(minLength: 0); remove }
                        mode
                        warning
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
            }
            if !track.triggers.isEmpty { Hairline() }
            HStack {
                Button("+ Add trigger") {
                    track.triggers.append(Trigger(combo: KeyCombo(key: .n, modifiers: [.control, .option]), mode: .toggle))
                }
                .buttonStyle(.vpGhost)
                if track.triggers.isEmpty {
                    Text("No hotkey yet: run it from the menu bar panel, or add one.").font(VPFont.caption).foregroundStyle(Palette.fgMuted)
                }
            }
            .padding(.horizontal, 6).padding(.vertical, 6)
        }
    }

    private var pipeline: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 4) {
                ForEach($track.steps) { $step in
                    StepRow(step: $step, speaker: app.speaker, expanded: expandedStep == step.id) {
                        expandedStep = expandedStep == step.id ? nil : step.id
                    } onDelete: {
                        track.steps.removeAll { $0.id == step.id }
                    } onDragStart: {
                        draggingStep = step.id
                    }
                    .onDrop(of: [.text], delegate: StepDropDelegate(target: step.id, steps: $track.steps, dragging: $draggingStep))
                    .id("step-\(step.id)")
                    .vpFlash("step-\(step.id)")
                }
            }
            HStack(spacing: 12) {
                addStepMenu
                if let error = track.validationError {
                    Text("WARN · " + error).font(VPFont.caption).foregroundStyle(Palette.orange)
                } else if !track.steps.isEmpty {
                    Text("✓ Steps connect: " + ([track.steps.first?.kind.input.rawValue ?? "none"]
                         + track.steps.map(\.kind.output.rawValue)).map { $0 == "none" ? "—" : $0 }.joined(separator: " → "))
                        .font(VPFont.caption).foregroundStyle(Palette.green)
                }
            }
        }
    }

    private var addStepMenu: some View {
        AddStepMenu(previous: track.steps.last?.kind) { kind in
            let step = Step(kind: kind)
            track.steps.append(step)
            expandedStep = step.id
        }
    }
}

/// "+ Add step": opens the step picker under it, told where the step goes (the track or a branch, after what).
private struct AddStepMenu: View {
    var branch: String?
    let previous: StepKind?
    let onAdd: (StepKind) -> Void
    @State private var anchor = AnchorBox()

    final class AnchorBox { weak var view: NSView? }

    var body: some View {
        Button {
            guard let view = anchor.view else { return }
            StepPickerPanel.show(from: view, context: StepPickerContext(
                branch: branch, previous: previous,
                hasOpenRouterKey: Keychain.get(SecretKey.openRouter) != nil, hasJevKey: JevClient.hasKey), onAdd: onAdd)
        } label: {
            Text("+ Add step").font(VPFont.bodyStrong).foregroundStyle(Palette.purple)
        }
        .buttonStyle(.plain)
        .background(AnchorView { anchor.view = $0 })
        .help("Add a block")
    }
}

/// A branch's own steps: the same rows as the track's pipeline, reorderable, with their own Add step.
private struct BranchSteps: View {
    @Binding var steps: [Step]
    let branchName: String
    let speaker: Speaker
    @State private var expandedStep: Step.ID?
    @State private var draggingStep: Step.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach($steps) { $step in
                StepRow(step: $step, speaker: speaker, expanded: expandedStep == step.id) {
                    expandedStep = expandedStep == step.id ? nil : step.id
                } onDelete: {
                    steps.removeAll { $0.id == step.id }
                } onDragStart: {
                    draggingStep = step.id
                }
                .onDrop(of: [.text], delegate: StepDropDelegate(target: step.id, steps: $steps, dragging: $draggingStep))
                .id("step-\(step.id)")
                .vpFlash("step-\(step.id)")
            }
            HStack(spacing: 10) {
                AddStepMenu(branch: branchName, previous: steps.last?.kind) { kind in
                    let step = Step(kind: kind)
                    steps.append(step)
                    expandedStep = step.id
                }
                if steps.isEmpty {
                    Text("no steps: the text passes through as it is").font(VPFont.caption).foregroundStyle(Palette.comment)
                }
            }
            .padding(.leading, 4)
        }
    }
}

/// One branch of a Branch block, as a card: its name and what Jev chooses it by (click ✎ to edit), then its steps.
private struct BranchEditor: View {
    let index: Int
    @Binding var branch: Branch
    let speaker: Speaker
    let onDelete: (() -> Void)?
    @State private var editing = false

    private static let colors = [Palette.green, Palette.cyan, Palette.purple, Palette.yellow, Palette.orange]
    private var color: Color { editing ? Palette.pink : Self.colors[index % Self.colors.count] }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if editing {
                    VPTextField("Name", text: $branch.name, font: VPFont.bodyStrong, color: Palette.pink)
                        .focusKey("branch\(index + 1).name").frame(width: 160)
                } else {
                    Text(branch.name.isEmpty ? "unnamed" : branch.name).font(VPFont.bodyStrong).foregroundStyle(color)
                }
                Spacer(minLength: 8)
                Button { editing.toggle() } label: { Image(systemName: editing ? "checkmark" : "pencil") }
                    .buttonStyle(.vpIcon).help(editing ? "Done" : "Edit the name and what Jev chooses it by")
                if let onDelete {
                    Button(action: onDelete) { Image(systemName: "trash") }.buttonStyle(.vpIcon).help("Remove this branch")
                }
            }
            if editing {
                FieldLabel("Use when", help: "Jev reads this to choose the branch.") {
                    VPTextField("Use when…", text: $branch.when, axis: .vertical, font: .system(size: 12, design: .monospaced), minHeight: 38)
                        .focusKey("branch\(index + 1).when")
                }
            } else {
                (Text("use when › ").foregroundColor(Palette.comment) + Text(branch.when.isEmpty ? "(no description: Jev can't pick it)" : branch.when))
                    .font(.system(size: 12, design: .monospaced)).foregroundStyle(Palette.fgMuted)
                    .lineLimit(2)
                    .onTapGesture { editing = true }
            }
            BranchSteps(steps: $branch.steps, branchName: branch.name.isEmpty ? "unnamed" : branch.name, speaker: speaker)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 4).fill(Palette.bg100))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(editing ? Palette.pink : Palette.line, lineWidth: 1))
        .id("branch-\(branch.id)")
        .vpFlash("branch-\(branch.id)")
    }
}

/// The track's colour square; click for the palette (or any colour).
private struct TrackColorMenu: View {
    @Binding var hex: String

    var body: some View {
        Menu {
            ForEach(Palette.trackSwatches, id: \.hex) { swatch in
                Button { hex = swatch.hex } label: {
                    Label { Text(swatch.name) } icon: { Image(nsImage: Self.swatch(swatch.hex, size: 10)) }
                }
            }
            Divider()
            Button("Other colour…") {
                ColorPanelTarget.shared.open(Color(hex: hex)) { color in
                    let c = color.usingColorSpace(.sRGB) ?? color
                    hex = String(format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
                }
            }
        } label: {
            Image(nsImage: Self.swatch(hex, size: 12))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Track colour")
        // This track's editor is going away: the colour panel must not write into it any more.
        .onDisappear { ColorPanelTarget.shared.detach() }
    }

    /// Drawn when shown, so a palette colour picks its Sundown or Daylight version.
    private static func swatch(_ hex: String, size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            NSColor(Palette.track(hex)).setFill()
            rect.fill()
            return true
        }
        return image
    }
}

/// Bridges the shared colour panel to a closure. One long-lived instance: NSColorPanel doesn't retain its target.
private final class ColorPanelTarget: NSObject {
    static let shared = ColorPanelTarget()
    private var onChange: ((NSColor) -> Void)?

    func open(_ color: Color, onChange: @escaping (NSColor) -> Void) {
        let panel = NSColorPanel.shared
        // Setting the colour sends the action at once, so detach first and attach the new closure after.
        self.onChange = nil
        panel.setTarget(self)
        panel.setAction(#selector(changed(_:)))
        panel.showsAlpha = false
        panel.color = NSColor(color)
        self.onChange = onChange
        panel.orderFront(nil)
    }

    func detach() {
        onChange = nil
        if NSColorPanel.shared.isVisible { NSColorPanel.shared.close() }
    }

    @objc private func changed(_ panel: NSColorPanel) { onChange?(panel.color) }
}

/// One block of the pipeline: handle, category tile, category and title, its types, expand and delete. Expanded,
/// its settings sit under it, indented to the title, and the row is outlined in lavender.
private struct StepRow: View {
    @Binding var step: Step
    let speaker: Speaker
    let expanded: Bool
    let onToggle: () -> Void
    let onDelete: () -> Void
    let onDragStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text("⋮⋮")
                    .font(VPFont.body).tracking(-2)
                    .foregroundStyle(Palette.comment)
                    .frame(width: 16, height: 28)
                    .contentShape(Rectangle())
                    .onHover { inside in inside ? NSCursor.openHand.push() : NSCursor.pop() }
                    .onDrag {
                        onDragStart()
                        return NSItemProvider(object: step.id.uuidString as NSString)
                    }
                    .help("Drag to reorder")
                Image(systemName: step.kind.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 2).fill(step.kind.tint.opacity(0.15)))
                    .foregroundStyle(step.kind.tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(step.kind.category.uppercased()).font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(0.8).foregroundStyle(step.kind.tint).lineLimit(1).fixedSize()
                    Text(step.kind.title).font(VPFont.bodyStrong).lineLimit(1)
                }
                .layoutPriority(1)
                Spacer(minLength: 8)
                // The types give way first in a narrow window.
                Text("\(step.kind.input.rawValue == "none" ? "—" : step.kind.input.rawValue) → \(step.kind.output.rawValue == "none" ? "—" : step.kind.output.rawValue)")
                    .font(VPFont.caption).foregroundStyle(Palette.fgMuted).lineLimit(1)
                Button(action: onToggle) { Image(systemName: expanded ? "chevron.up" : "chevron.down") }
                    .buttonStyle(.vpIcon).help(expanded ? "Hide settings" : "Settings")
                Button(action: onDelete) { Image(systemName: "trash") }.buttonStyle(.vpIcon).help("Remove this step")
            }
            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    StepConfigView(kind: $step.kind, stepID: step.id, speaker: speaker)
                }
                .padding(.leading, 66).padding(.bottom, 4)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 4).fill(Palette.bg200))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(expanded ? Palette.purple : Palette.line, lineWidth: 1))
    }

}

/// Reorders steps live as a dragged step passes over the others; the drop itself just ends the drag.
private struct StepDropDelegate: DropDelegate {
    let target: Step.ID
    @Binding var steps: [Step]
    @Binding var dragging: Step.ID?

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target,
              let from = steps.firstIndex(where: { $0.id == dragging }),
              let to = steps.firstIndex(where: { $0.id == target }) else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            steps.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

/// Edits the associated values of a step kind in place.
private struct StepConfigView: View {
    @Binding var kind: StepKind
    let stepID: Step.ID
    let speaker: Speaker
    @Environment(\.appInput) private var appInput

    var body: some View {
        switch kind {
        case .microphone(let input):
            ConfigRow("Input") {
                InputPicker(selection: Binding { input } set: { kind = .microphone(input: $0) }, appDefault: appInput)
            }

        case .text(let sources):
            VStack(alignment: .leading, spacing: 4) {
                Text("Uses the first source that has text:").font(VPFont.caption).foregroundStyle(Palette.fgMuted)
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
            transcriptionPicker
            ConfigRow("Mode") {
                Picker("Mode", selection: Binding { mode } set: { kind = .parakeet(chunkOnPauseMs: pauseMs, mode: $0) }) {
                    ForEach(ParakeetMode.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden().fixedSize()
            }
            Text(mode.detail).font(VPFont.caption).foregroundStyle(Palette.fgMuted)
            if mode == .pauseChunks {
                HStack {
                    Text("Cut at pauses longer than").font(VPFont.caption).foregroundStyle(Palette.fgMuted)
                    Slider(value: Binding { Double(pauseMs) } set: { kind = .parakeet(chunkOnPauseMs: Int($0), mode: mode) },
                           in: 300...1200, step: 50)
                    Text("\(pauseMs) ms").monospacedDigit().frame(width: 60, alignment: .trailing)
                }
            }
            if mode != .onRelease {
                Text("Chunking and streaming apply when this step directly follows Microphone.")
                    .font(VPFont.caption).foregroundStyle(Palette.fgMuted)
            }

        case .openRouterSTT:
            transcriptionPicker

        case .llm(let model, let prompt, let policy):
            ConfigRow("Model") {
                ModelPicker(capability: .text, modelID: Binding { model } set: { kind = .llm(model: $0, prompt: prompt, onFailure: policy) })
            }
            ConfigRow("If it fails") {
                VPSegmented(selection: Binding { policy } set: { kind = .llm(model: model, prompt: prompt, onFailure: $0) },
                            options: [(.passThrough, "Pass input through"), (.stop, "Stop the track")])
            }
            FieldLabel("Instructions", help: "{{input}} places the text; otherwise it's sent as the user message.") {
                VPTextEditor(text: Binding { prompt } set: { kind = .llm(model: model, prompt: $0, onFailure: policy) })
                    .focusKey("prompt")
            }

        case .route(let routes):
            Text("Jev reads the text and picks the route whose description fits best (about 0.3 s); that route's model answers with its instructions. Without a Jev key, the first route is used.")
                .font(VPFont.caption).foregroundStyle(Palette.fgMuted)
            ForEach(Array(routes.enumerated()), id: \.element.id) { index, route in
                RouteEditor(stepID: stepID, index: index, route: Binding {
                    routes[index]
                } set: { updated in
                    var all = routes
                    all[index] = updated
                    kind = .route(routes: all)
                }, onDelete: routes.count > 1 ? {
                    kind = .route(routes: routes.filter { $0.id != route.id })
                } : nil)
            }
            Button("+ Add route") {
                kind = .route(routes: routes + [Route(name: "route \(routes.count + 1)", when: "",
                                                      model: "anthropic/claude-haiku-4.5", prompt: "")])
            }
            .buttonStyle(.vpGhost).padding(.leading, -8)

        case .branch(let question, let branches):
            Text("Jev answers the question about the text (about 0.3 s) and picks the branch whose description fits; that branch's steps run, then the track carries on. Without a Jev key, the first branch runs.")
                .font(VPFont.caption).foregroundStyle(Palette.fgMuted)
            FieldLabel("Question", help: "What Jev decides, e.g. how hard the text is to read aloud, or what it's about.") {
                VPTextField("What should Jev decide about the text?", text: Binding { question ?? "" } set: {
                    kind = .branch(question: $0.isEmpty ? nil : $0, branches: branches)
                }, axis: .vertical).focusKey("question")
            }
            ForEach(Array(branches.enumerated()), id: \.element.id) { index, branch in
                BranchEditor(index: index, branch: Binding {
                    branches[index]
                } set: { updated in
                    var all = branches
                    all[index] = updated
                    kind = .branch(question: question, branches: all)
                }, speaker: speaker, onDelete: branches.count > 1 ? {
                    kind = .branch(question: question, branches: branches.filter { $0.id != branch.id })
                } : nil)
            }
            Button("+ Add branch") {
                kind = .branch(question: question, branches: branches + [Branch(name: "branch \(branches.count + 1)", when: "", steps: [])])
            }
            .buttonStyle(.vpGhost).padding(.leading, -8)

        case .http(let url, let method, let headers, let body, let field):
            let set = { (u: String, m: String, h: [String: String], b: String, f: String) in
                kind = .http(url: u, method: m, headers: h, bodyTemplate: b, responseField: f)
            }
            ConfigRow("Method") {
                VPSegmented(selection: Binding { method } set: { set(url, $0, headers, body, field) },
                            options: ["GET", "POST", "PUT", "PATCH"].map { ($0, $0) })
            }
            FieldLabel("URL", help: "{{input}} here is URL-encoded.") {
                VPTextField("https://…", text: Binding { url } set: { set($0, method, headers, body, field) }).focusKey("url")
            }
            FieldLabel("Headers", help: "Name: value, one per line.") {
              VPTextField("Authorization: Bearer …", text: Binding {
                headers.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
            } set: { text in
                let parsed = text.split(separator: "\n").reduce(into: [String: String]()) { dict, line in
                    let parts = line.split(separator: ":", maxSplits: 1)
                    if parts.count == 2 { dict[parts[0].trimmingCharacters(in: .whitespaces)] = parts[1].trimmingCharacters(in: .whitespaces) }
                }
                set(url, method, parsed, body, field)
              }, axis: .vertical).focusKey("headers")
            }
            FieldLabel("Body", help: "{{input}} or {{input_json}} (a JSON string).") {
                VPTextField("{\"text\": {{input_json}}}", text: Binding { body } set: { set(url, method, headers, $0, field) },
                            axis: .vertical, font: .system(size: 12, design: .monospaced), minHeight: 64).focusKey("body")
            }
            FieldLabel("Response field", help: "A dotted path into the JSON response, e.g. data.text; empty uses the whole body.") {
                VPTextField("data.text", text: Binding { field } set: { set(url, method, headers, body, $0) }).focusKey("response_field")
            }

        case .template(let template):
            FieldLabel("Template", help: "{{input}} or {{input_json}} places the text.") {
                VPTextField("{{input}}", text: Binding { template } set: { kind = .template($0) }, axis: .vertical,
                            font: .system(size: 12, design: .monospaced), minHeight: 64)
                    .focusKey("template")
            }

        case .fixWords:
            FixWordsSummary()

        case .paste(let restore):
            Toggle("Restore previous clipboard after pasting", isOn: Binding { restore } set: { kind = .paste(restoreClipboard: $0) })

        case .copy:
            Text("Leaves the text on the clipboard.").font(VPFont.caption).foregroundStyle(Palette.fgMuted)

        case .speak(let voiceID, let rate):
            speechPicker
            ConfigRow("Voice") {
                Picker("Voice", selection: Binding { voiceID ?? "" } set: { kind = .speak(voiceID: $0.isEmpty ? nil : $0, rate: rate) }) {
                    Text("System default (best installed)").tag("")
                    ForEach(Self.voices, id: \.identifier) { voice in
                        Text("\(voice.name) · \(voice.quality == .premium ? "Premium" : voice.quality == .enhanced ? "Enhanced" : "Default")")
                            .tag(voice.identifier)
                    }
                }
                .labelsHidden().frame(maxWidth: 280)
            }
            HStack {
                Text("Speed").font(VPFont.caption).foregroundStyle(Palette.fgMuted).frame(width: 90, alignment: .leading)
                Slider(value: Binding { Double(rate) } set: { kind = .speak(voiceID: voiceID, rate: Float($0)) }, in: 0.6...2.0, step: 0.1)
                Text(String(format: "%.1f×", rate)).monospacedDigit().frame(width: 44, alignment: .trailing)
            }

        case .openRouterSpeech(let model, let voice, let rate):
            speechPicker
            ConfigRow("Voice") {
                VoicePicker(modelID: model, voice: Binding { voice } set: { kind = .openRouterSpeech(model: model, voice: $0, rate: rate) },
                            speaker: speaker)
            }
            HStack {
                Text("Speed").font(VPFont.caption).foregroundStyle(Palette.fgMuted).frame(width: 90, alignment: .leading)
                Slider(value: Binding { Double(rate) } set: { kind = .openRouterSpeech(model: model, voice: voice, rate: Float($0)) },
                       in: 0.6...2.0, step: 0.1)
                Text(String(format: "%.1f×", rate)).monospacedDigit().frame(width: 44, alignment: .trailing)
            }
            Text("Long text is read in passages: the first starts within a second or two, the next downloads while you listen.")
                .font(VPFont.caption).foregroundStyle(Palette.fgMuted)

        case .localSpeech(let engine, let voice, let rate):
            speechPicker
            ConfigRow("Voice") {
                HStack {
                    Picker("Voice", selection: Binding { voice } set: { kind = .localSpeech(engine: engine, voice: $0, rate: rate) }) {
                        ForEach(engine.voices, id: \.self) { Text(engine.voiceLabel($0)).tag($0) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 220)
                    LocalPreviewButton(engine: engine, voice: voice, speaker: speaker)
                }
            }
            HStack {
                Text("Speed").font(VPFont.caption).foregroundStyle(Palette.fgMuted).frame(width: 90, alignment: .leading)
                Slider(value: Binding { Double(rate) } set: { kind = .localSpeech(engine: engine, voice: voice, rate: Float($0)) },
                       in: 0.6...2.0, step: 0.1)
                Text(String(format: "%.1f×", rate)).monospacedDigit().frame(width: 44, alignment: .trailing)
            }
            Text(engine.detail).font(VPFont.caption).foregroundStyle(Palette.fgMuted)

        case .showHUD:
            Text("Shows the text in the HUD for a few seconds.").font(VPFont.caption).foregroundStyle(Palette.fgMuted)
        }
    }

    static let parakeetOption = LocalModelOption(id: "local:parakeet", name: "Parakeet v3",
                                                 detail: "NVIDIA's model, on this Mac · about 50–150 ms after you stop")
    static let speechOptions = [
        LocalModelOption(id: "local:pocket", name: "Pocket TTS", detail: "Streams as it speaks · first sound in ~20 ms · 26 voices"),
        LocalModelOption(id: "local:supertonic", name: "Supertonic-3", detail: "~80× faster than real time · small · 10 voices"),
        LocalModelOption(id: "local:macos", name: "macOS voices", detail: "The voices installed in System Settings"),
    ]

    /// Transcribe is one block: Parakeet on this Mac, or any OpenRouter transcription model.
    private var transcriptionPicker: some View {
        let selection = switch kind {
        case .openRouterSTT(let model): model
        default: Self.parakeetOption.id
        }
        return ConfigRow("Model") {
            ModelPicker(capability: .transcription, selection: selection, local: [Self.parakeetOption]) { pick in
                switch pick {
                case .local:
                    if case .parakeet = kind { return }
                    kind = .parakeet(chunkOnPauseMs: 500, mode: .onRelease)
                case .openRouter(let model):
                    kind = .openRouterSTT(model: model.id)
                }
            }
        }
    }

    /// Speak is one block: an on-device model, a macOS voice, or any OpenRouter speech model. Speed carries over.
    private var speechPicker: some View {
        let (selection, rate, currentVoice): (String, Float, String?) = switch kind {
        case .localSpeech(let engine, let voice, let r): ("local:\(engine.rawValue)", r, voice)
        case .openRouterSpeech(let model, let voice, let r): (model, r, voice)
        case .speak(_, let r): ("local:macos", r, nil)
        default: ("", 1, nil)
        }
        return ConfigRow("Model") {
            ModelPicker(capability: .speech, selection: selection, local: Self.speechOptions) { pick in
                switch pick {
                case .local(let option) where option.id == "local:macos":
                    kind = .speak(voiceID: nil, rate: rate)
                case .local(let option):
                    let engine = LocalVoiceEngine(rawValue: String(option.id.dropFirst("local:".count))) ?? .pocket
                    let voice = currentVoice.flatMap { engine.voices.contains($0) ? $0 : nil } ?? engine.defaultVoice
                    kind = .localSpeech(engine: engine, voice: voice, rate: rate)
                case .openRouter(let model):
                    let voice = currentVoice.flatMap { model.voices.contains($0) ? $0 : nil } ?? model.defaultVoice ?? ""
                    kind = .openRouterSpeech(model: model.id, voice: voice, rate: rate)
                }
            }
        }
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
        // A keycap; pink (the keyboard colour) while it listens for the new shortcut.
        Button { recording ? stop() : start() } label: {
            Text(recording ? "Press keys…" : combo.display)
                .font(VPFont.bodyStrong)
                .foregroundStyle(recording ? Palette.pink : Palette.fg)
                .padding(.horizontal, 10).frame(minWidth: 80, minHeight: 24)
                .background(RoundedRectangle(cornerRadius: 2).fill(recording ? Color.clear : Palette.bg300))
                .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(recording ? Palette.pink : Palette.line, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

/// Plays a short sample of an on-device voice (downloading the engine the first time).
private struct LocalPreviewButton: View {
    let engine: LocalVoiceEngine
    let voice: String
    let speaker: Speaker
    @State private var playing = false
    @State private var error: String?

    var body: some View {
        Button {
            if playing {
                speaker.clear()
                playing = false
                return
            }
            playing = true
            error = nil
            Task {
                do { try await speaker.previewLocal(engine: engine, voice: voice) } catch { self.error = error.localizedDescription }
                playing = false
            }
        } label: {
            Image(systemName: playing ? "stop.fill" : "play.fill")
        }
        .buttonStyle(.vpIcon)
        .help(error ?? "Preview this voice (first use downloads the model)")
    }
}

/// One route of a Route step, as a card: its name (in the route's colour) and model; then what Jev chooses by
/// ("use when ›"). Click it to edit: the card is outlined in rose and shows the fields.
private struct RouteEditor: View {
    let stepID: Step.ID
    let index: Int
    @Binding var route: Route
    let onDelete: (() -> Void)?
    @State private var editing = false

    private static let colors = [Palette.green, Palette.cyan, Palette.purple, Palette.yellow, Palette.orange]
    private var color: Color { editing ? Palette.pink : Self.colors[index % Self.colors.count] }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if editing {
                    VPTextField("Name", text: $route.name, font: VPFont.bodyStrong, color: Palette.pink)
                        .focusKey("route\(index + 1).name").frame(width: 160)
                } else {
                    Text(route.name.isEmpty ? "unnamed" : route.name).font(VPFont.bodyStrong).foregroundStyle(color)
                }
                Spacer(minLength: 8)
                ModelPicker(capability: .text, modelID: $route.model)
                Button { editing.toggle() } label: { Image(systemName: editing ? "checkmark" : "pencil") }
                    .buttonStyle(.vpIcon).help(editing ? "Done" : "Edit this route")
                if let onDelete {
                    Button(action: onDelete) { Image(systemName: "trash") }.buttonStyle(.vpIcon).help("Remove this route")
                }
            }
            if editing {
                FieldLabel("Use when", help: "Jev reads this to choose the route.") {
                    VPTextField("Use when…", text: $route.when, axis: .vertical, font: .system(size: 12, design: .monospaced), minHeight: 38)
                        .focusKey("route\(index + 1).when")
                }
                FieldLabel("Instructions", help: "{{input}} places the text.") {
                    VPTextField("Instructions", text: $route.prompt, axis: .vertical, font: .system(size: 12, design: .monospaced), minHeight: 64)
                        .focusKey("route\(index + 1).prompt")
                }
            } else {
                (Text("use when › ").foregroundColor(Palette.comment) + Text(route.when.isEmpty ? "(no description: Jev can't pick it)" : route.when))
                    .font(.system(size: 12, design: .monospaced)).foregroundStyle(Palette.fgMuted)
                    .lineLimit(2)
                    .onTapGesture { editing = true }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 4).fill(Palette.bg100))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(editing ? Palette.pink : Palette.line, lineWidth: 1))
        .id("route-\(route.id)")
        .vpFlash("route-\(route.id)")
        .onAppear { takeRequest(); report() }
        .onChange(of: UINav.shared.openRoute) { _, _ in takeRequest() }
        .onChange(of: editing) { _, _ in report() }
        .onDisappear { UINav.shared.editingRoutes.removeAll { $0 == index + 1 } }
    }

    private func takeRequest() {
        guard let request = UINav.shared.openRoute, request.step == stepID, request.index == index else { return }
        UINav.shared.openRoute = nil
        editing = true
    }

    private func report() {
        var routes = UINav.shared.editingRoutes.filter { $0 != index + 1 }
        if editing { routes.append(index + 1) }
        UINav.shared.editingRoutes = routes.sorted()
    }
}

/// A setting with its label in a fixed caption column.
private struct ConfigRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content
    init(_ label: String, @ViewBuilder content: () -> Content) { self.label = label; self.content = content() }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(label).font(VPFont.caption).foregroundStyle(Palette.fgMuted).frame(width: 90, alignment: .leading)
            content
            Spacer(minLength: 0)
        }
    }
}

/// A field with a caption above and optional help below.
private struct FieldLabel<Content: View>: View {
    let label: String
    var help: String?
    @ViewBuilder let content: Content
    init(_ label: String, help: String? = nil, @ViewBuilder content: () -> Content) {
        self.label = label; self.help = help; self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(VPFont.caption).foregroundStyle(Palette.fgMuted)
            content
            if let help { Text(help).font(VPFont.caption).foregroundStyle(Palette.fgMuted) }
        }
    }
}

/// The Fix words step uses the shared list; this shows how many words it has and links to it.
private struct FixWordsSummary: View {
    var body: some View {
        let count = VocabularyStore.shared.entries.count
        Text("Replaces mishearings from your Vocabulary (\(count) \(count == 1 ? "word" : "words")) — instant, no model. Edit the list under Vocabulary in the sidebar.")
            .font(VPFont.caption).foregroundStyle(Palette.fgMuted)
    }
}
