import SwiftUI

/// The model picker's list: every model that can do the job, with what a typical job costs, how fast it is on this
/// Mac, and how good it is, ranked four ways. Numbers come from ModelInsights; missing ones say so.
struct ModelBrowser: View {
    let capability: OpenRouterCatalog.Capability
    let selection: String
    let local: [LocalModelOption]
    let onPick: (ModelPicker.Pick) -> Void
    let onClose: () -> Void
    var onHeight: (CGFloat) -> Void = { _ in }
    /// Harness only.
    var initialQuery = ""
    var initialSort: ModelInsights.Sort?

    static let width: CGFloat = 500
    static let maxHeight: CGFloat = 600
    private static let rowHeight: CGFloat = 52

    @State private var query = ""
    @State private var sort: ModelInsights.Sort = .value
    @State private var highlighted: String?
    @State private var expanded: String?
    @FocusState private var searchFocused: Bool

    private var catalog: OpenRouterCatalog { .shared }
    private var sortKey: String { "picker.sort." + ModelInsights.sourceKey(capability) }

    // MARK: Data

    private struct Row: Identifiable {
        let id: String
        let name: String
        let local: Bool
        let provider: String
        let detail: String?
        let info: ModelInsights.Info
        var description: String?
    }

    private var allRows: [Row] {
        let localRows = local.map { option in
            Row(id: option.id, name: option.name, local: true, provider: "on this Mac", detail: option.detail,
                info: ModelInsights.info(option.id, capability), description: option.detail)
        }
        let cloud = catalog.models(for: capability).map { model in
            Row(id: model.id, name: Self.displayName(model), local: false, provider: model.provider, detail: detail(model),
                info: ModelInsights.info(model.id, capability), description: model.description)
        }
        return localRows + cloud
    }

    /// The free tier's "(free)" / "Free" suffix goes: the cost cell and the rate-limited tag already say it.
    static func displayName(_ model: OpenRouterCatalog.Model) -> String {
        var name = model.shortName
        guard model.id.hasSuffix(":free") else { return name }
        for suffix in [" (free)", " Free"] where name.hasSuffix(suffix) { name.removeLast(suffix.count) }
        return name
    }

    private func detail(_ model: OpenRouterCatalog.Model) -> String? {
        switch capability {
        case .speech: model.voices.isEmpty ? nil : "\(model.voices.count) voices"
        case .text: model.context_length.map { $0 >= 1_000_000 ? "\($0 / 1_000_000)M" : "\($0 / 1000)K" }
        case .transcription: nil
        }
    }

    private var filtered: [Row] {
        let terms = query.lowercased().split(separator: " ")
        return allRows.filter { row in
            let hay = "\(row.name) \(row.id) \(row.provider) \(row.detail ?? "") \(row.info.tags.joined(separator: " "))".lowercased()
            return terms.allSatisfy { hay.contains($0) }
        }
    }

    /// On this Mac is pinned on top in every sort (free, private, offline: a different choice, not a point on the
    /// same curve); each group is ordered by the current sort.
    private var groups: [(title: String?, rows: [Row])] {
        let rows = filtered
        let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        func ordered(_ subset: [Row]) -> [Row] { ModelInsights.order(subset.map(\.id), capability, by: sort).compactMap { byID[$0] } }
        return [("On this Mac", ordered(rows.filter(\.local))), ("OpenRouter", ordered(rows.filter { !$0.local }))].filter { !$0.rows.isEmpty }
    }

    private var flatIDs: [String] { groups.flatMap { $0.rows.map(\.id) } }

    /// Only one row gets the top badge: the first OpenRouter row under the current sort that has the measure.
    private var topID: String? {
        let ids = ModelInsights.order(filtered.filter { !$0.local }.map(\.id), capability, by: sort)
        guard let first = ids.first else { return nil }
        let info = ModelInsights.info(first, capability)
        switch sort {
        case .value: return ModelInsights.value(info) != nil ? first : nil
        case .quality: return info.quality != nil ? first : nil
        case .speed: return info.ms != nil ? first : nil
        case .cost: return info.cost != nil ? first : nil
        }
    }

    private var topLabel: String {
        switch sort {
        case .value: "BEST VALUE"
        case .quality: "TOP QUALITY"
        case .speed: "FASTEST"
        case .cost: "CHEAPEST"
        }
    }

    // MARK: Layout

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            columns
            Hairline()
            if flatIDs.isEmpty {
                Text("No model matches \"\(query)\".").font(VPFont.caption).foregroundStyle(Palette.fgMuted)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(14)
            } else {
                list
            }
            Hairline()
            footer
        }
        .frame(width: Self.width)
        .background(Palette.bg000)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.line, lineWidth: 1))
        .background(GeometryReader { geo in Color.clear.preference(key: BrowserHeight.self, value: geo.size.height) })
        .onPreferenceChange(BrowserHeight.self, perform: onHeight)
        .onAppear {
            if let stored = UserDefaults.standard.string(forKey: sortKey), let saved = ModelInsights.Sort(rawValue: stored) { sort = saved }
            if let initialSort { sort = initialSort }
            if !initialQuery.isEmpty { query = initialQuery }
            highlighted = selection
            searchFocused = true
        }
        .onChange(of: sort) { _, new in UserDefaults.standard.set(new.rawValue, forKey: sortKey) }
    }

    private var title: String {
        switch capability {
        case .speech: "Speech models"
        case .text: "Language models"
        case .transcription: "Transcription models"
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.system(size: 15, weight: .bold, design: .monospaced)).foregroundStyle(Palette.fg)
                Spacer()
                Text("\(allRows.count) · " + (catalog.updated.map { Calendar.current.isDateInToday($0) ? "refreshed today" : "refreshed \($0.shortAgo)" } ?? "not refreshed yet"))
                    .font(VPFont.caption).foregroundStyle(Palette.fgMuted)
            }
            TextField("", text: $query, prompt: Text("Search models, voices or providers").foregroundStyle(Palette.fgMuted))
                .textFieldStyle(.plain).font(.system(size: 13, design: .monospaced))
                .focused($searchFocused)
                .padding(.horizontal, 10).frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 4).fill(Palette.bg200))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.line, lineWidth: 1))
                .vpFocusRing(searchFocused)
                .onKeyPress(.downArrow) { move(1); return .handled }
                .onKeyPress(.upArrow) { move(-1); return .handled }
                .onKeyPress(.rightArrow) { expanded = highlighted; return .handled }
                .onKeyPress(.leftArrow) { expanded = nil; return .handled }
                .onKeyPress(.escape) { onClose(); return .handled }
                .onSubmit(pickHighlighted)
            VPSegmented(selection: $sort, options: [(.value, "Best value"), (.quality, "Quality"), (.speed, "Speed"), (.cost, "Cost")])
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    private var latencyTitle: String {
        switch capability {
        case .speech: "1st sound"
        case .text: "Reply"
        case .transcription: "After stop"
        }
    }

    private var columns: some View {
        HStack(spacing: 10) {
            columnTitle("Model", active: false).frame(maxWidth: .infinity, alignment: .leading)
            columnTitle("Paragraph", active: sort == .cost).frame(width: 78, alignment: .trailing)
            columnTitle(latencyTitle, active: sort == .speed).frame(width: 70, alignment: .trailing)
            columnTitle("Quality", active: sort == .quality || sort == .value).frame(width: 64, alignment: .trailing)
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
    }

    private func columnTitle(_ text: String, active: Bool) -> some View {
        Text(text.uppercased() + (active ? " ▾" : "")).font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(0.8)
            .foregroundStyle(active ? Palette.purple : Palette.fgMuted).lineLimit(1)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 8)
                    ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                        if let title = group.title {
                            Text(title.uppercased()).font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1)
                                .foregroundStyle(Palette.fgMuted).padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 4)
                        }
                        ForEach(group.rows) { row in rowView(row).id(row.id) }
                    }
                }
                .padding(.bottom, 20)
            }
            .scrollIndicators(.never)
            // Rows fade under the column header and above the footer instead of being cut mid-line.
            .mask(
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 24)
                    Rectangle().fill(.black)
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 24)
                }
            )
            .frame(height: listHeight)
            .onAppear { proxy.scrollTo(selection, anchor: .center) }
            .onChange(of: highlighted) { _, id in if let id { proxy.scrollTo(id) } }
        }
    }

    private var listHeight: CGFloat {
        let content = CGFloat(flatIDs.count) * Self.rowHeight + CGFloat(groups.filter { $0.title != nil }.count) * 28 + (expanded != nil ? 70 : 0) + 6
        return min(content, Self.maxHeight - 250)
    }

    private func rowView(_ row: Row) -> some View {
        let selected = row.id == selection
        let on = highlighted == row.id
        let open = expanded == row.id
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(row.name + (selected ? " ✓" : "")).font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundStyle(Palette.fg)
                    .lineLimit(1).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
                costText(row).frame(width: 78, alignment: .trailing)
                latencyText(row).frame(width: 70, alignment: .trailing)
                QualitySquares(score: row.info.quality).frame(width: 64, alignment: .trailing)
            }
            HStack(spacing: 6) {
                // The badge counts toward the two tags, so the provider line never truncates.
                if row.id == topID { tag(topLabel, filled: true) }
                ForEach(Array(row.info.tags.prefix(row.id == topID ? 1 : 2)), id: \.self) { tag($0, filled: false) }
                Text([row.local ? nil : row.provider, row.detail].compactMap { $0 }.joined(separator: " · "))
                    .font(VPFont.caption).foregroundStyle(Palette.fgMuted).lineLimit(1)
            }
            if open { expandedView(row) }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .frame(minHeight: Self.rowHeight, alignment: .top)
        .background(selected || on ? Palette.bg300 : Color.clear)
        .overlay(alignment: .leading) { if selected { Rectangle().fill(Palette.purple).frame(width: 3) } }
        .contentShape(Rectangle())
        .onHover { if $0 { highlighted = row.id } }
        .onTapGesture { expanded = open ? nil : row.id; highlighted = row.id }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private func expandedView(_ row: Row) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(sentence(row)).font(.system(size: 12, design: .monospaced)).foregroundStyle(Palette.fg).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Use \(row.name)") { pick(row.id) }.buttonStyle(.vpSecondary)
            }
        }
        .padding(.top, 4)
    }

    /// The curated selling point; else the catalogue's first sentence; for on-device models, their benchmark note.
    private func sentence(_ row: Row) -> String {
        var text = row.info.sentence ?? firstSentence(row.description) ?? ""
        if row.info.costFromRuns { text += (text.isEmpty ? "" : " ") + "Cost from your runs." }
        return text.isEmpty ? row.id : text
    }

    private func firstSentence(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        let end = text.firstIndex { ".!?".contains($0) }.map { text.index(after: $0) } ?? text.endIndex
        let sentence = String(text[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        return sentence.count > 180 ? String(sentence.prefix(177)) + "…" : sentence
    }

    private func costText(_ row: Row) -> some View {
        Group {
            if let cost = row.info.cost {
                Text(cost == 0 ? "free" : RunLogFormat.cost(cost)).foregroundStyle(Palette.fg)
            } else {
                Text("—").foregroundStyle(Palette.comment)
            }
        }
        .font(.system(size: 12, design: .monospaced)).monospacedDigit()
    }

    private func latencyText(_ row: Row) -> some View {
        Group {
            if let ms = row.info.ms { Text(Self.seconds(ms)).foregroundStyle(Palette.fg) } else { Text("—").foregroundStyle(Palette.comment) }
        }
        .font(.system(size: 12, design: .monospaced)).monospacedDigit()
    }

    static func seconds(_ ms: Int) -> String { ms < 1000 ? String(format: "%.2f s", Double(ms) / 1000) : String(format: "%.1f s", Double(ms) / 1000) }

    private func tag(_ text: String, filled: Bool) -> some View {
        Text(text).font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(0.4)
            .foregroundStyle(filled ? Palette.onAccent : Palette.fg)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 2).fill(filled ? Palette.purple : Palette.bg200))
            .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(filled ? Color.clear : Palette.line, lineWidth: 1))
            .fixedSize()
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(footnoteShort).font(VPFont.caption).foregroundStyle(Palette.fgMuted).lineLimit(2)
                Image(systemName: "info.circle").font(.system(size: 11)).foregroundStyle(Palette.fgMuted).help(footnote)
                    .accessibilityLabel(footnote)
            }
            HStack(spacing: 10) {
                Text("Or a model id").font(VPFont.caption).foregroundStyle(Palette.fgMuted).fixedSize()
                ModelIDField { id in
                    if id.contains("/") { onPick(.openRouter(catalog.model(id) ?? .init(id: id, name: id))) }
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    /// One line; the full definition is in the ⓘ tooltip.
    private var footnoteShort: String {
        let source = ModelInsights.ratings.sources[ModelInsights.sourceKey(capability)]
        let quality = source.map { "Quality: \($0.name)\($0.date.map { ", \($0)" } ?? "")" } ?? "Quality: not rated yet"
        switch capability {
        case .speech: return "Paragraph ≈ 600 chars · \(quality) · 1st sound: your last 20 runs"
        case .text: return "Paragraph ≈ 150 in + 150 out · \(quality) · Reply: your last 20 runs"
        case .transcription: return "Paragraph ≈ 30 s audio · \(quality) · After stop: your last 20 runs"
        }
    }

    private var footnote: String {
        let source = ModelInsights.ratings.sources[ModelInsights.sourceKey(capability)]
        let quality = source.map { "Quality: \($0.name)\($0.date.map { ", \($0)" } ?? "")." } ?? "Quality: not rated yet."
        switch capability {
        case .speech:
            return "Paragraph = about 100 words (600 characters, ~40 s of speech), priced in each model's billing unit; — when the unit isn't known. \(quality) 1st sound: measured on this Mac, median of your last 20 runs; — until you have one."
        case .text:
            return "Paragraph = about 150 tokens in and 150 out, plus any per-request fee. \(quality) Reply: the full reply time, measured on this Mac, median of your last 20 runs."
        case .transcription:
            return "Paragraph = 30 s of audio, priced in each model's billing unit, then from your own runs once you have them. \(quality) After stop: from key-up to text, measured on this Mac."
        }
    }

    // MARK: Keyboard

    private func move(_ delta: Int) {
        let ids = flatIDs
        guard !ids.isEmpty else { return }
        let current = highlighted.flatMap { ids.firstIndex(of: $0) } ?? -1
        highlighted = ids[max(0, min(ids.count - 1, current + delta))]
    }

    private func pickHighlighted() {
        if let id = highlighted ?? flatIDs.first { pick(id) }
    }

    private func pick(_ id: String) {
        if let option = local.first(where: { $0.id == id }) {
            onPick(.local(option))
        } else if let model = catalog.model(id) {
            onPick(.openRouter(model))
        }
    }
}

/// Quality as five squares (filled = the score), or "not rated".
private struct QualitySquares: View {
    let score: Int?

    var body: some View {
        if let score {
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { i in
                    Rectangle().fill(i < score ? Palette.fg : Palette.line).frame(width: 8, height: 8)
                }
            }
            .accessibilityLabel("Quality \(score) of 5")
        } else {
            Text("not rated").font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.comment).fixedSize()
        }
    }
}

/// "provider/model", Return to use it.
private struct ModelIDField: View {
    let onSubmit: (String) -> Void
    @State private var text = ""

    var body: some View {
        TextField("", text: $text, prompt: Text("provider/model").foregroundStyle(Palette.fgMuted))
            .textFieldStyle(.plain).font(.system(size: 12, design: .monospaced))
            .padding(.horizontal, 8).frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 4).fill(Palette.bg200))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.line, lineWidth: 1))
            .onSubmit { onSubmit(text.trimmingCharacters(in: .whitespaces)) }
    }
}

private struct BrowserHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
