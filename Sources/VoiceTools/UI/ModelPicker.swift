import SwiftUI

/// A button showing the chosen OpenRouter model; clicking opens a searchable list of models that can do the job.
struct ModelPicker: View {
    let capability: OpenRouterCatalog.Capability
    @Binding var modelID: String
    var onChange: ((OpenRouterCatalog.Model) -> Void)?

    @State private var showing = false
    private var catalog: OpenRouterCatalog { .shared }

    var body: some View {
        Button { showing = true } label: {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(catalog.model(modelID)?.shortName ?? modelID).lineLimit(1)
                    Text(modelID).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            ModelList(capability: capability, selection: modelID) { model in
                modelID = model.id
                onChange?(model)
                showing = false
            }
        }
        .onAppear { catalog.refreshIfStale() }
    }
}

private struct ModelList: View {
    let capability: OpenRouterCatalog.Capability
    let selection: String
    let pick: (OpenRouterCatalog.Model) -> Void
    @State private var query = ""
    private var catalog: OpenRouterCatalog { .shared }

    private var models: [OpenRouterCatalog.Model] {
        let all = catalog.models(for: capability)
        let terms = query.lowercased().split(separator: " ")
        guard !terms.isEmpty else { return all }
        return all.filter { model in
            let haystack = "\(model.name) \(model.id)".lowercased()
            return terms.allSatisfy { haystack.contains($0) }
        }
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
            TextField("Search \(catalog.models(for: capability).count) models", text: $query)
                .textFieldStyle(.roundedBorder)
            if let error = catalog.error {
                Text(error).font(.caption).foregroundStyle(.orange)
            }
            List(models) { model in
                Button { pick(model) } label: {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.shortName).fontWeight(model.id == selection ? .semibold : .regular)
                            Text(model.id).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(model.priceLabel(for: capability)).font(.caption).foregroundStyle(.secondary)
                            if capability == .speech, !model.voices.isEmpty {
                                Text("\(model.voices.count) voices").font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        if model.id == selection { Image(systemName: "checkmark").foregroundStyle(.tint) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            HStack {
                Text("Or type a model id:").font(.caption).foregroundStyle(.secondary)
                TextField("provider/model", text: $query, onCommit: {
                    let id = query.trimmingCharacters(in: .whitespaces)
                    if id.contains("/") { pick(catalog.model(id) ?? .init(id: id, name: id)) }
                })
                .font(.system(size: 11, design: .monospaced))
                .textFieldStyle(.roundedBorder)
            }
        }
        .padding(12)
        .frame(width: 440, height: 460)
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
