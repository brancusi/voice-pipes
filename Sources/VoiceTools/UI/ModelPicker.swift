import SwiftUI

/// A model that runs on this Mac, listed above OpenRouter's models in a picker.
struct LocalModelOption: Identifiable, Hashable {
    /// Distinct from OpenRouter ids, which always contain a "/".
    let id: String
    let name: String
    let detail: String
}

/// One picker for every model that can do a job: on-device models first, then OpenRouter's live list.
struct ModelPicker: View {
    enum Pick {
        case local(LocalModelOption)
        case openRouter(OpenRouterCatalog.Model)
    }

    let capability: OpenRouterCatalog.Capability
    let selection: String
    var local: [LocalModelOption] = []
    let onPick: (Pick) -> Void

    @State private var anchor = AnchorBox()
    private var catalog: OpenRouterCatalog { .shared }

    final class AnchorBox { weak var view: NSView? }

    init(capability: OpenRouterCatalog.Capability, selection: String, local: [LocalModelOption] = [],
         onPick: @escaping (Pick) -> Void) {
        self.capability = capability
        self.selection = selection
        self.local = local
        self.onPick = onPick
    }

    /// OpenRouter-only picker bound to a model id.
    init(capability: OpenRouterCatalog.Capability, modelID: Binding<String>) {
        self.init(capability: capability, selection: modelID.wrappedValue) { pick in
            if case .openRouter(let model) = pick { modelID.wrappedValue = model.id }
        }
    }

    var body: some View {
        Button(action: open) {
            HStack(spacing: 8) {
                if let option = local.first(where: { $0.id == selection }) {
                    Text(option.name).foregroundStyle(Palette.fg).lineLimit(1)
                    Text("on this Mac").foregroundStyle(Palette.fgMuted).lineLimit(1)
                } else {
                    Text(catalog.model(selection)?.shortName ?? selection).foregroundStyle(Palette.fg).lineLimit(1)
                    if let price = catalog.model(selection)?.shortPrice(for: capability) {
                        Text(price).foregroundStyle(Palette.fgMuted).lineLimit(1)
                    }
                }
                Text("▾").foregroundStyle(Palette.fgMuted)
            }
            .font(.system(size: 12, design: .monospaced))
            .padding(.horizontal, 8).frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 4).fill(Palette.bg300))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(AnchorView { anchor.view = $0 })
        .help(local.contains { $0.id == selection } ? "Runs on this Mac" : "OpenRouter · \(selection)")
        .onAppear { catalog.refreshIfStale() }
    }

    private func open() {
        guard let view = anchor.view else { return }
        let capability = capability, selection = selection, local = local, onPick = onPick
        AnchoredPanel.shared.show(from: view, width: ModelBrowser.width, maxHeight: ModelBrowser.maxHeight) { close, report in
            ModelBrowser(capability: capability, selection: selection, local: local, onPick: { pick in
                onPick(pick)
                close()
            }, onClose: close, onHeight: report)
        }
    }
}

/// Picks one of the voices a speech model offers, with a ▶ preview for each.
struct VoicePicker: View {
    let modelID: String
    @Binding var voice: String
    let speaker: Speaker

    @State private var showing = false
    @State private var query = ""
    @State private var previewing: String?
    @State private var previewError: String?
    private var catalog: OpenRouterCatalog { .shared }

    private var voices: [String] {
        let all = catalog.model(modelID)?.voicesEnglishFirst ?? []
        guard !query.isEmpty else { return all }
        return all.filter { "\($0) \(OpenRouterCatalog.Model.voiceLabel($0))".lowercased().contains(query.lowercased()) }
    }

    var body: some View {
        HStack {
            Button { showing = true } label: {
                HStack(spacing: 8) {
                    Text(voice.isEmpty ? "Choose a voice" : OpenRouterCatalog.Model.voiceLabel(voice)).foregroundStyle(Palette.fg).lineLimit(1)
                    Text("▾").foregroundStyle(Palette.fgMuted)
                }
                .font(.system(size: 12, design: .monospaced))
                .padding(.horizontal, 8).frame(height: 24)
                .background(RoundedRectangle(cornerRadius: 4).fill(Palette.bg300))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showing, arrowEdge: .bottom) { list }
            previewButton(voice)
        }
        if let previewError { Text(previewError).font(VPFont.caption).foregroundStyle(Palette.orange).lineLimit(3) }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Voices · \(catalog.model(modelID)?.shortName ?? modelID)").font(VPFont.title)
            if (catalog.model(modelID)?.voices ?? []).isEmpty {
                Text("OpenRouter doesn't list voices for this model. Type a voice id, or leave it empty for the model's default.")
                    .font(VPFont.caption).foregroundStyle(Palette.fgMuted)
                VPTextField("Voice id", text: $voice)
            } else {
                VPTextField("Search voices", text: $query)
                List(voices, id: \.self) { id in
                    HStack {
                        Button {
                            voice = id
                            showing = false
                        } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(OpenRouterCatalog.Model.voiceLabel(id)).fontWeight(id == voice ? .semibold : .regular)
                                Text(id).font(VPFont.micro).foregroundStyle(Palette.fgMuted)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        previewButton(id)
                        if id == voice { Text("✓").foregroundStyle(Palette.purple) }
                    }
                }
                .listStyle(.plain)
            }
        }
        .padding(12)
        .frame(width: 380, height: 420)
        .background(Palette.bg200)
        .vpWindow()
    }

    private func previewButton(_ id: String) -> some View {
        Button {
            if previewing == id {
                speaker.clear()
                previewing = nil
                return
            }
            previewing = id
            previewError = nil
            Task {
                do { try await speaker.preview(model: modelID, voice: id) } catch { previewError = error.localizedDescription }
                if previewing == id { previewing = nil }
            }
        } label: {
            Image(systemName: previewing == id ? "stop.fill" : "play.fill")
        }
        .buttonStyle(.vpIcon)
        .help("Preview this voice")
        .disabled(id.isEmpty && !(catalog.model(modelID)?.voices ?? []).isEmpty)
    }
}
