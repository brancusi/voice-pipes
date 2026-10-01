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

    @State private var showing = false
    private var catalog: OpenRouterCatalog { .shared }

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
        Button { showing = true } label: {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    if let option = local.first(where: { $0.id == selection }) {
                        Text(option.name).lineLimit(1)
                        Text("On this Mac").font(.system(size: 10)).foregroundStyle(.secondary)
                    } else {
                        Text(catalog.model(selection)?.shortName ?? selection).lineLimit(1)
                        Text("OpenRouter · \(selection)").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            ModelList(capability: capability, selection: selection, local: local) { pick in
                onPick(pick)
                showing = false
            }
        }
        .onAppear { catalog.refreshIfStale() }
    }
}

private struct ModelList: View {
    let capability: OpenRouterCatalog.Capability
    let selection: String
    let local: [LocalModelOption]
    let pick: (ModelPicker.Pick) -> Void
    @State private var query = ""
    private var catalog: OpenRouterCatalog { .shared }

    private var terms: [Substring] { query.lowercased().split(separator: " ") }

    private func matches(_ text: String) -> Bool {
        let haystack = text.lowercased()
        return terms.allSatisfy { haystack.contains($0) }
    }

    private var localMatches: [LocalModelOption] { local.filter { matches("\($0.name) \($0.detail) local mac") } }
    private var models: [OpenRouterCatalog.Model] {
        catalog.models(for: capability).filter { matches("\($0.name) \($0.id)") }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(capability.title).font(.headline)
                Spacer()
                if catalog.loading { ProgressView().controlSize(.small) }
                Button { catalog.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).help("Reload the list from OpenRouter")
            }
            TextField("Search \(local.count + catalog.models(for: capability).count) models", text: $query)
                .textFieldStyle(.roundedBorder)
            if let error = catalog.error {
                Text(error).font(.caption).foregroundStyle(.orange)
            }
            List {
                if !localMatches.isEmpty {
                    Section("On this Mac") {
                        ForEach(localMatches) { option in
                            row(title: option.name, subtitle: option.detail, trailing: "free", selected: option.id == selection) {
                                pick(.local(option))
                            }
                        }
                    }
                }
                Section("OpenRouter") {
                    ForEach(models) { model in
                        row(title: model.shortName, subtitle: model.id, mono: true,
                            trailing: model.priceLabel(for: capability),
                            extra: capability == .speech && !model.voices.isEmpty ? "\(model.voices.count) voices" : nil,
                            selected: model.id == selection) {
                            pick(.openRouter(model))
                        }
                    }
                }
            }
            .listStyle(.plain)
            HStack {
                Text("Or type an OpenRouter model id:").font(.caption).foregroundStyle(.secondary)
                TextField("provider/model", text: $query, onCommit: {
                    let id = query.trimmingCharacters(in: .whitespaces)
                    if id.contains("/") { pick(.openRouter(catalog.model(id) ?? .init(id: id, name: id))) }
                })
                .font(.system(size: 11, design: .monospaced))
                .textFieldStyle(.roundedBorder)
            }
        }
        .padding(12)
        .frame(width: 460, height: 480)
    }

    private func row(title: String, subtitle: String, mono: Bool = false, trailing: String, extra: String? = nil,
                     selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).fontWeight(selected ? .semibold : .regular)
                    Text(subtitle).font(mono ? .system(size: 10, design: .monospaced) : .system(size: 11))
                        .foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(trailing).font(.caption).foregroundStyle(.secondary)
                    if let extra { Text(extra).font(.caption2).foregroundStyle(.tertiary) }
                }
                if selected { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                HStack {
                    Text(voice.isEmpty ? "Choose a voice" : OpenRouterCatalog.Model.voiceLabel(voice)).lineLimit(1)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.bordered)
            .popover(isPresented: $showing, arrowEdge: .bottom) { list }
            previewButton(voice)
        }
        if let previewError { Text(previewError).font(.caption).foregroundStyle(.orange).lineLimit(3) }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Voices · \(catalog.model(modelID)?.shortName ?? modelID)").font(.headline)
            if (catalog.model(modelID)?.voices ?? []).isEmpty {
                Text("OpenRouter doesn't list voices for this model. Type a voice id, or leave it empty for the model's default.")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("Voice id", text: $voice).textFieldStyle(.roundedBorder)
            } else {
                TextField("Search voices", text: $query).textFieldStyle(.roundedBorder)
                List(voices, id: \.self) { id in
                    HStack {
                        Button {
                            voice = id
                            showing = false
                        } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(OpenRouterCatalog.Model.voiceLabel(id)).fontWeight(id == voice ? .semibold : .regular)
                                Text(id).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        previewButton(id)
                        if id == voice { Image(systemName: "checkmark").foregroundStyle(.tint) }
                    }
                }
                .listStyle(.plain)
            }
        }
        .padding(12)
        .frame(width: 380, height: 420)
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
            Image(systemName: previewing == id ? "stop.circle" : "play.circle")
        }
        .buttonStyle(.borderless)
        .help("Preview this voice")
        .disabled(id.isEmpty && !(catalog.model(modelID)?.voices ?? []).isEmpty)
    }
}
