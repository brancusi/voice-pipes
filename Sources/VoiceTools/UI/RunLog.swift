import AppKit
import SwiftUI

// MARK: Numbers

/// What runs used, summed: tokens, exact cost (LLMs, transcription) and estimated cost (cloud speech).
struct UsageSummary {
    var runs = 0
    var promptTokens = 0
    var completionTokens = 0
    var exact = 0.0
    var estimated = 0.0

    var usedCloud: Bool { promptTokens + completionTokens > 0 || exact > 0 || estimated > 0 }

    mutating func add(_ usage: RunRecord.Usage) {
        guard usage.local != true else { return }
        promptTokens += usage.promptTokens ?? 0
        completionTokens += usage.completionTokens ?? 0
        if usage.estimated == true { estimated += usage.cost ?? 0 } else { exact += usage.cost ?? 0 }
    }

    init() {}

    init(_ records: some Sequence<RunRecord>) {
        for record in records {
            runs += 1
            for entry in record.log ?? [] { if let usage = entry.usage { add(usage) } }
        }
    }

    /// "412 → 61 tok · $0.0027 + ≈$0.0004", or nil when nothing was used in the cloud.
    var line: String? {
        var parts: [String] = []
        if promptTokens + completionTokens > 0 { parts.append("\(RunLogFormat.count(promptTokens)) → \(RunLogFormat.count(completionTokens)) tok") }
        if exact > 0 || estimated > 0 {
            parts.append([exact > 0 ? RunLogFormat.cost(exact) : nil, estimated > 0 ? "≈" + RunLogFormat.cost(estimated) : nil]
                .compactMap { $0 }.joined(separator: " + "))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

enum RunLogFormat {
    /// "$0.0027" under a cent, "$0.041", "$1.27".
    static func cost(_ value: Double) -> String {
        value < 0.01 ? String(format: "$%.4f", value) : value < 1 ? String(format: "$%.3f", value) : String(format: "$%.2f", value)
    }

    /// 412, 12.3k, 1.2M.
    static func count(_ n: Int) -> String {
        n < 1000 ? "\(n)" : n < 1_000_000 ? String(format: "%.1fk", Double(n) / 1000) : String(format: "%.1fM", Double(n) / 1_000_000)
    }

    /// "96 ms", "1,180 ms", "2.6 s".
    static func ms(_ ms: Int) -> String {
        ms < 2000 ? "\(ms.formatted()) ms" : String(format: "%.1f s", Double(ms) / 1000)
    }

    /// The usage column for a step.
    static func usage(_ entry: RunRecord.LogEntry, showDecision: Bool = true) -> String {
        switch entry.status {
        case .passedThrough: return "ERR · passed input through"
        case .failed: return "ERR · stopped the run"
        case .ok: break
        }
        if showDecision, let decision = entry.decision {
            return decision.confidence.map { "Jev → \(decision.chosen) \(Int($0 * 100))%" } ?? "Jev unavailable → \(decision.chosen)"
        }
        // The recording: its length is already in the time column.
        if entry.category == "Input", let out = entry.output, out.hasPrefix("audio") { return "" }
        let firstSound = entry.firstSoundMs.map { "1st sound \(ms($0))" }
        guard let usage = entry.usage else { return [entry.voice, firstSound].compactMap { $0 }.joined(separator: " · ") }
        if usage.local == true { return [entry.voice, firstSound, "on this Mac"].compactMap { $0 }.joined(separator: " · ") }
        var parts: [String] = [entry.voice, firstSound].compactMap { $0 }
        if let p = usage.promptTokens, let c = usage.completionTokens { parts.append("\(count(p)) → \(count(c)) tok") }
        if let seconds = usage.seconds { parts.append(String(format: "%.1f s audio", seconds)) }
        if let characters = usage.characters { parts.append("\(characters.formatted()) chars") }
        if let cost = usage.cost { parts.append((usage.estimated == true ? "≈" : "") + Self.cost(cost)) }
        return parts.joined(separator: " · ")
    }
}

extension RunRecord {
    var passedThroughCount: Int { (log ?? []).filter { $0.status == .passedThrough }.count }

    /// The whole log as plain text, one step per line, indented for branches.
    var logText: String {
        var lines = ["\(trackName) · \(date.formatted(date: .abbreviated, time: .shortened)) · \(RunLogFormat.ms(totalMs))"]
        for entry in log ?? [] {
            let indent = String(repeating: "  ", count: entry.depth + 1)
            var line = "\(indent)\(entry.title)  \(RunLogFormat.ms(entry.ms))"
            let usage = RunLogFormat.usage(entry)
            if !usage.isEmpty { line += "  \(usage)" }
            if let decision = entry.decision, !decision.others.isEmpty { line += "  (not taken: \(decision.others.joined(separator: ", ")))" }
            lines.append(line)
            if let message = entry.message, entry.status != .ok { lines.append("\(indent)  ! \(message)") }
            if let out = entry.output, !out.hasPrefix("audio") { lines.append("\(indent)  OUT \(out)") }
        }
        lines.append("  Total  \(RunLogFormat.ms(totalMs))  \(UsageSummary([self]).line ?? "on this Mac")")
        return lines.joined(separator: "\n")
    }
}

// MARK: Totals strip

/// Top of History: what today and the last 7 days used.
struct UsageTotalsStrip: View {
    let records: [RunRecord]

    var body: some View {
        let now = Date()
        let today = UsageSummary(records.filter { Calendar.current.isDateInToday($0.date) })
        let week = UsageSummary(records.filter { now.timeIntervalSince($0.date) < 7 * 86_400 })
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 22) {
                todayParts(today)
                Spacer(minLength: 12)
                weekPart(week)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 14) { label("Today"); number("\(today.runs)", "runs") }
                tokensAndCost(today)
                weekPart(week)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .vpCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Usage totals")
    }

    @ViewBuilder private func todayParts(_ s: UsageSummary) -> some View {
        label("Today").frame(width: 64, alignment: .leading)
        number("\(s.runs)", "runs")
        tokensAndCost(s)
    }

    @ViewBuilder private func tokensAndCost(_ s: UsageSummary) -> some View {
        if s.usedCloud {
            HStack(alignment: .firstTextBaseline, spacing: 22) {
                if s.promptTokens + s.completionTokens > 0 {
                    number("\(RunLogFormat.count(s.promptTokens)) → \(RunLogFormat.count(s.completionTokens))", "tokens")
                }
                number(RunLogFormat.cost(s.exact), s.estimated > 0 ? "+ ≈\(RunLogFormat.cost(s.estimated)) speech" : "")
            }
        } else {
            Text("on this Mac").font(VPFont.caption).foregroundStyle(Palette.fgMuted)
        }
    }

    private func weekPart(_ s: UsageSummary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            label("7 days")
            // Wraps rather than ever cutting off a cost.
            Text("\(s.runs) runs" + (s.line.map { " · \($0)" } ?? " · on this Mac"))
                .font(VPFont.caption).foregroundStyle(Palette.fg).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text.uppercased()).font(VPFont.label).tracking(0.9).foregroundStyle(Palette.fgMuted)
    }

    private func number(_ value: String, _ unit: String) -> some View {
        (Text(value).font(.system(size: 15, weight: .bold, design: .monospaced)).foregroundColor(Palette.fg)
            + Text(unit.isEmpty ? "" : " " + unit).font(VPFont.caption).foregroundColor(Palette.fgMuted))
            .monospacedDigit().lineLimit(1)
    }
}

// MARK: The log

/// One run's log, under its History row: every step with its time and usage, its output, the path a Branch or
/// Route took (a purple rail), and the total.
struct RunLogView: View {
    let record: RunRecord

    /// A Branch and the steps it ran, or one step.
    private indirect enum Node: Identifiable {
        case step(Int)
        case branch(Int, [Node])
        var id: Int { switch self { case .step(let i), .branch(let i, _): i } }
    }

    private var entries: [RunRecord.LogEntry] { record.log ?? [] }

    private var tree: [Node] {
        var index = 0
        return Self.build(entries, &index, depth: 0)
    }

    private static func build(_ entries: [RunRecord.LogEntry], _ index: inout Int, depth: Int) -> [Node] {
        var nodes: [Node] = []
        while index < entries.count, entries[index].depth >= depth {
            let i = index
            index += 1
            guard entries[i].depth == depth else { continue }
            if entries[i].decision?.kind == "branch" {
                nodes.append(.branch(i, build(entries, &index, depth: depth + 1)))
            } else {
                nodes.append(.step(i))
            }
        }
        return nodes
    }

    var body: some View {
        GeometryReader { geo in
            content(narrow: geo.size.width < 560)
                .frame(width: geo.size.width, alignment: .leading)
                .background(GeometryReader { inner in Color.clear.preference(key: LogHeight.self, value: inner.size.height) })
        }
        .frame(height: height)
        .onPreferenceChange(LogHeight.self) { height = $0 }
        .background(Palette.bg000)
    }

    @State private var height: CGFloat = 40

    private func content(narrow: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(tree) { node in nodeView(node, narrow: narrow) }
            Rectangle().fill(Palette.line).frame(height: 1).padding(.top, 6)
            StepLine(square: nil, title: "Total", titleColor: Palette.fgMuted, time: RunLogFormat.ms(record.totalMs), timeColor: Palette.fg,
                     usage: UsageSummary([record]).line ?? "on this Mac", usageColor: Palette.fg, narrow: narrow)
        }
        .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 12)
    }

    private func nodeView(_ node: Node, narrow: Bool) -> AnyView {
        switch node {
        case .step(let i):
            return AnyView(stepView(i, narrow: narrow))
        case .branch(let i, let children):
            let entry = entries[i]
            return AnyView(VStack(alignment: .leading, spacing: 2) {
                StepLine(square: entry.kind.tint, title: "Branch · Jev", time: RunLogFormat.ms(entry.ms),
                         usage: RunLogFormat.usage(entry), usageColor: Palette.purple, narrow: narrow)
                rail(narrow: narrow) {
                    Text("branch \(entry.decision?.chosen ?? "")").font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Palette.purple).padding(.vertical, 2)
                    if children.isEmpty {
                        Text("no steps: the text passed through").font(VPFont.caption).foregroundStyle(Palette.fgMuted)
                    }
                    ForEach(children) { nodeView($0, narrow: narrow) }
                }
                notTaken(entry, narrow: narrow)
            })
        }
    }

    @ViewBuilder private func stepView(_ i: Int, narrow: Bool) -> some View {
        let entry = entries[i]
        if let decision = entry.decision, decision.kind == "route" {
            // One step that is two things: Jev's pick, then the chosen route's model answering.
            StepLine(square: entry.kind.tint, title: "Route · Jev", time: RunLogFormat.ms(decision.jevMs),
                     usage: RunLogFormat.usage(entry), usageColor: Palette.purple, narrow: narrow)
            rail(narrow: narrow) {
                StepLine(square: entry.kind.tint, title: "LLM · \(entry.usage?.model ?? decision.chosen)",
                         time: RunLogFormat.ms(max(0, entry.ms - decision.jevMs)),
                         usage: RunLogFormat.usage(entry, showDecision: false), usageColor: usageColor(entry), narrow: narrow)
                output(i, narrow: narrow)
            }
            notTaken(entry, narrow: narrow)
        } else {
            StepLine(square: entry.kind.tint, title: entry.title, time: RunLogFormat.ms(entry.ms),
                     usage: RunLogFormat.usage(entry), usageColor: usageColor(entry), narrow: narrow)
            output(i, narrow: narrow)
        }
    }

    private func usageColor(_ entry: RunRecord.LogEntry) -> Color {
        entry.status == .ok ? Palette.fgMuted : Palette.orange
    }

    /// The step's OUT line; for a failure, what happened and what the next step got instead.
    @ViewBuilder private func output(_ i: Int, narrow: Bool) -> some View {
        let entry = entries[i]
        if entry.status != .ok {
            OutLine(text: failureText(i), color: Palette.orange, narrow: narrow)
        } else if let out = entry.output, !out.hasPrefix("audio") {
            OutLine(text: out, color: Palette.fgMuted, narrow: narrow)
        }
    }

    private func failureText(_ i: Int) -> String {
        let entry = entries[i]
        let message = entry.message ?? "failed"
        guard entry.status == .passedThrough else { return message }
        let next = entries[(i + 1)...].first { $0.depth <= entry.depth }?.title
        let source = i > 0 ? entries[i - 1].title : "the step before"
        return message + (next.map { " \($0) got the text from \(source) instead." } ?? "")
    }

    private func rail<Content: View>(narrow: Bool, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) { content() }
            .padding(.leading, narrow ? 10 : 12)
            .overlay(alignment: .leading) { Rectangle().fill(Palette.purple).frame(width: 2) }
            .padding(.leading, narrow ? 4 : 20)
    }

    @ViewBuilder private func notTaken(_ entry: RunRecord.LogEntry, narrow: Bool) -> some View {
        if let others = entry.decision?.others, !others.isEmpty {
            Text("not taken: " + others.joined(separator: " · "))
                .font(VPFont.caption).foregroundStyle(Palette.comment)
                .padding(.leading, narrow ? 18 : 34).padding(.top, 2).padding(.bottom, 4)
        }
    }

    private struct LogHeight: PreferenceKey {
        static let defaultValue: CGFloat = 40
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
    }
}

/// One line of the log: category square · title · time · usage (narrow: usage under the title).
private struct StepLine: View {
    let square: Color?
    let title: String
    var titleColor: Color = Palette.fg
    let time: String
    var timeColor: Color = Palette.fgMuted
    let usage: String
    var usageColor: Color = Palette.fgMuted
    let narrow: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Rectangle().fill(square ?? .clear).frame(width: 7, height: 7).frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(titleColor)
                    .lineLimit(1).truncationMode(.tail)
                if narrow, !usage.isEmpty { usageText }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(time).font(.system(size: 12, design: .monospaced)).monospacedDigit().foregroundStyle(timeColor)
                .frame(width: 72, alignment: .trailing)
            // A fixed column, so every time lines up; long usage wraps to a second line rather than clipping.
            if !narrow {
                usageText.frame(width: 220, alignment: .leading)
            }
        }
        .padding(.vertical, 4)
    }

    private var usageText: some View {
        Text(usage).font(VPFont.caption).monospacedDigit().foregroundStyle(usageColor)
            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
    }
}

/// "OUT the text…", one line with "more" to read it all (scrolls past 240 pt).
private struct OutLine: View {
    let text: String
    let color: Color
    let narrow: Bool
    @State private var open = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("OUT").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(Palette.comment)
            if open {
                ScrollView {
                    Text(text).font(.system(size: 12, design: .monospaced)).foregroundStyle(color).lineSpacing(3)
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 240).fixedSize(horizontal: false, vertical: true)
            } else {
                Text(text.replacingOccurrences(of: "\n", with: " ")).font(.system(size: 12, design: .monospaced)).foregroundStyle(color)
                    .lineLimit(1).truncationMode(.tail)
            }
            // Only when it can't fit on its line (a rough measure: mono 12-pt glyphs are ~7.2 pt wide).
            if text.count > (narrow ? 34 : 96) || text.contains("\n") {
                Button(open ? "less" : "more") { open.toggle() }
                    .buttonStyle(.plain).font(.system(size: 12, design: .monospaced)).foregroundStyle(Palette.purple)
                    .fixedSize()
            }
        }
        .padding(.leading, 24).padding(.bottom, 2)
    }
}

extension RunRecord.LogEntry {
    /// The category colour, as the editor uses it.
    var kind: StepKindTint { StepKindTint(category: category) }
}

/// A category's colour without a StepKind (log entries keep the category name).
struct StepKindTint {
    let category: String?
    var tint: Color {
        switch category {
        case "Input": Palette.fgMuted
        case "Transcribe": Palette.cyan
        case "Output": Palette.green
        default: Palette.purple
        }
    }
}
