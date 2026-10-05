import SwiftUI

/// Record a word several times back to back, run every variation through Parakeet, have Jev judge which
/// mishearings are safe to replace, and pick which to add.
struct TrainWordSheet: View {
    let parakeet: ParakeetService
    @Binding var entry: VocabularyEntry
    @Environment(\.dismiss) private var dismiss

    #if SNAPSHOTS
    /// Harness only: before training, with sentences already written.
    static func setupPreview() -> some View {
        var sheet = TrainWordSheet(parakeet: ParakeetService(), entry: .constant(VocabularyEntry(write: "TUI", heardAs: [])))
        sheet._sentences = State(initialValue: ["I prefer using a TUI because it's faster than clicking through menus.",
                                                "The TUI application loaded instantly on my terminal this morning.",
                                                "I don't want to go back to graphical apps after using this TUI.",
                                                "This TUI makes it easy to navigate without touching the mouse.",
                                                "TUI tools feel lighter than most desktop apps I've used.",
                                                "Can you show me how to build a simple TUI?"])
        sheet._hint = State(initialValue: "terminal user interface")
        return sheet
    }
    #endif

    /// `input`: the mic to record from (the app's, so words are trained on the mic you dictate with).
    init(parakeet: ParakeetService, entry: Binding<VocabularyEntry>, input: String = AudioInputs.system) {
        self.parakeet = parakeet
        _entry = entry
        _recorder = State(initialValue: AudioRecorder(input: input))
    }

    @State private var recorder: AudioRecorder
    @State private var takes: [VocabularyTrainer.Take] = []
    /// The sentences to read: written for this word by `TrainingSentences`, else the built-in ones.
    @State private var sentences: [String] = []
    @State private var writingSentences = false
    /// What the word is, in your words: helps the sentences when it has several meanings ("terminal user interface").
    @State private var hint = ""
    @State private var sentencesNote: String?
    /// Jev's probability from which a result is ticked (the slider); kept between sessions. 30%: measured 2026-10-05,
    /// Jev's numbers run low, and 30% ticked 29 of 32 real garbles and 3 of 19 real words (60% ticked only 6 garbles).
    @AppStorage("vocabulary.threshold") private var threshold = 0.3
    @State private var recording = false
    @State private var takeStarted = Date()
    @State private var level: Float = 0
    @State private var useVoices = true
    @State private var phase: Phase = .idle
    @State private var done = 0
    @State private var total = 0
    @State private var report: VocabularyTrainer.Report?
    @State private var verdicts: [String: Double] = [:]
    @State private var selected: Set<String> = []
    @State private var message: String?
    @State private var trainedSeconds: Double = 0

    private enum Phase { case idle, transcribing, judging }
    private var spelling: String { entry.write.trimmingCharacters(in: .whitespaces) }
    private var busy: Bool { phase != .idle }

    #if SNAPSHOTS
    /// Harness only: the sheet after a finished training run.
    static func preview() -> some View {
        let report = VocabularyTrainer.Report(results: [
            .init(text: "aram zedickian", count: 38, fromYou: 30, fromVoices: 8, commonWords: false),
            .init(text: "aaron zadikian", count: 22, fromYou: 20, fromVoices: 2, commonWords: false),
            .init(text: "a ram zadikyan", count: 17, fromYou: 17, fromVoices: 0, commonWords: false),
            .init(text: "aaron's attacking", count: 6, fromYou: 6, fromVoices: 0, commonWords: true),
            .init(text: "erin zadig", count: 1, fromYou: 1, fromVoices: 0, commonWords: false),
        ], correct: 41, total: 150)
        let verdicts = ["aram zedickian": 0.97, "aaron zadikian": 0.91, "a ram zadikyan": 0.88, "aaron's attacking": 0.04, "erin zadig": 0.52]
        return TrainWordSheet(parakeet: ParakeetService(), entry: .constant(VocabularyEntry(write: "Aram Zadikian", heardAs: [])),
                              preview: (report, verdicts, 5, 4.8))
    }

    init(parakeet: ParakeetService, entry: Binding<VocabularyEntry>,
         preview: (VocabularyTrainer.Report, [String: Double], Int, Double)) {
        self.parakeet = parakeet
        _entry = entry
        _recorder = State(initialValue: AudioRecorder())
        _report = State(initialValue: preview.0)
        _verdicts = State(initialValue: preview.1)
        _takes = State(initialValue: Array(repeating: VocabularyTrainer.Take(samples: [], sentence: ""), count: preview.2))
        _trainedSeconds = State(initialValue: preview.3)
        _selected = State(initialValue: Set(preview.1.filter { $0.value >= 0.3 }.map(\.key)))
    }
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let report {
                successCard(report)
                results(report)
            } else {
                setup
            }
            if let message { Text(message).font(VPFont.caption).foregroundStyle(Palette.orange) }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Text(report == nil || !verdicts.isEmpty ? "" : "Repeats that aren't ordinary words are pre-ticked.")
                    .font(VPFont.caption).foregroundStyle(Palette.fgMuted)
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.vpSecondary).keyboardShortcut(.cancelAction)
                Button("Add \(selected.count) to Heard as") { add() }
                    .buttonStyle(.vpPrimary)
                    .disabled(selected.isEmpty || busy)
            }
        }
        .padding(28)
        .frame(width: 640)
        .frame(minHeight: 300)
        .background(Palette.bg100)
        .vpWindow()
        .onAppear { if sentences.isEmpty, report == nil { writeSentences() } }
        .onDisappear { if recording { _ = recorder.stop() } }
    }

    /// Before training: what to do, the takes, and the Train button with its progress.
    private var setup: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Train “\(spelling)”").font(VPFont.title)
            Text("Click **Start takes** and read the sentence out loud, the way you'd dictate it; **Next take** shows the next one. About five takes. Words are misheard differently in a sentence than on their own, so only the part where “\(spelling)” was is kept. Each take is replayed about 30 ways (speed, volume, background noise) through Parakeet. \(JevClient.hasKey ? "Jev then judges which results are safe to replace everywhere." : "Add a Jev key in Setup to have each result judged automatically.")")
                .font(VPFont.caption).lineSpacing(2).foregroundStyle(Palette.fgMuted)
                .fixedSize(horizontal: false, vertical: true)

            if recording {
                // The sentence to read, big enough to read from a step back.
                VStack(alignment: .leading, spacing: 4) {
                    Text("Say").font(VPFont.label).tracking(0.9).foregroundStyle(Palette.fgMuted)
                    Text("“\(currentSentence)”").font(VPFont.title).foregroundStyle(Palette.fg)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(Palette.bg200))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.red.opacity(0.6), lineWidth: 1))
            }
            if !recording { sentencesCard }
            recordingControls

            HStack(spacing: 8) {
                VPCheckbox(isOn: $useVoices, label: "Also have other voices say it").disabled(busy)
                Text("Also have other voices read them (on-device and Mac voices, two sentences each)")
                    .font(VPFont.caption).foregroundStyle(Palette.fgMuted)
                    .onTapGesture { if !busy { useVoices.toggle() } }
            }

            HStack(spacing: 10) {
                Button("Train") { train() }
                    .buttonStyle(.vpPrimary)
                    .disabled(busy || recording || spelling.isEmpty || (takes.isEmpty && !useVoices))
                switch phase {
                case .transcribing:
                    ProgressBar(value: total > 0 ? Double(done) / Double(total) : 0).frame(width: 200)
                    Text("\(done) / \(total)").font(VPFont.caption).monospacedDigit().foregroundStyle(Palette.fgMuted)
                case .judging:
                    ProgressView().controlSize(.small)
                    Text("Asking Jev…").font(VPFont.caption).foregroundStyle(Palette.fgMuted)
                case .idle:
                    EmptyView()
                }
                Spacer()
            }
        }
    }

    /// After training: the Wrangler's wink, a flavour headline, and the plain numbers.
    private func successCard(_ report: VocabularyTrainer.Report) -> some View {
        HStack(alignment: .center, spacing: 20) {
            Wrangler(pose: .done, scale: 3)
            VStack(alignment: .leading, spacing: 6) {
                PixelHeadline(report.results.isEmpty ? "already broke in" : "roped and branded", size: 20)
                Text(summary(report)).font(VPFont.body).lineSpacing(3).foregroundStyle(Palette.fgMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Button("↻ Record more takes") { self.report = nil; verdicts = [:]; selected = [] }
                    .buttonStyle(.vpGhost).padding(.leading, -8)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 6).fill(Palette.bg200))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.green, lineWidth: 1))
    }

    private func summary(_ report: VocabularyTrainer.Report) -> String {
        var parts = ["“\(spelling)” · \(takes.count) \(takes.count == 1 ? "take" : "takes"), \(report.total) variants in \(String(format: "%.1f", trainedSeconds)) s."]
        parts.append("Already right in \(report.correct) of \(report.total).")
        if !verdicts.isEmpty { parts.append("Jev judged \(verdicts.count) \(verdicts.count == 1 ? "result" : "results").") }
        if report.results.isEmpty { parts.append("Nothing else came out: it's already reliable.") }
        return parts.joined(separator: " ")
    }

    // MARK: - Recording

    private var recordingControls: some View {
        HStack(spacing: 10) {
            if recording {
                Rectangle().fill(Palette.red).frame(width: 7, height: 7)
                Text("REC").font(VPFont.label).tracking(0.9).foregroundStyle(Palette.red)
                Text("take \(takes.count + 1)").font(VPFont.caption).foregroundStyle(Palette.fgMuted)
                LevelBars(level: level)
                TimelineView(.periodic(from: takeStarted, by: 0.1)) { context in
                    Text(String(format: "%.1fs", context.date.timeIntervalSince(takeStarted)))
                        .font(VPFont.caption).monospacedDigit().foregroundStyle(Palette.fgMuted)
                }
                Spacer()
                Button("Next take") { nextTake() }.buttonStyle(.vpSecondary).keyboardShortcut(.space, modifiers: [])
                Button("Finish") { finishTakes() }.buttonStyle(.vpPrimary).keyboardShortcut(.return, modifiers: [])
            } else {
                Button { startTakes() } label: { Label(takes.isEmpty ? "Start takes" : "Record more takes", systemImage: "mic") }
                    .buttonStyle(.vpSecondary)
                    .disabled(busy || writingSentences)
                ForEach(takes.indices, id: \.self) { i in
                    HStack(spacing: 4) {
                        Text("\(i + 1) · \(String(format: "%.1f", Double(takes[i].samples.count) / 16_000))s")
                            .help(takes[i].sentence)
                        Button { takes.remove(at: i) } label: { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }
                            .buttonStyle(.plain).foregroundStyle(Palette.fgMuted)
                            .help("Remove this take")
                    }
                    .font(VPFont.caption).monospacedDigit().foregroundStyle(Palette.fgMuted)
                    .padding(.horizontal, 6).frame(height: 20)
                    .background(RoundedRectangle(cornerRadius: 2).fill(Palette.bg300))
                }
                Spacer()
            }
        }
        .padding(.horizontal, 12).frame(minHeight: 40)
        .vpCard()
    }

    private func startTakes() {
        message = nil
        recorder.onLevel = { value in Task { @MainActor in level = value } }
        do {
            try recorder.start()
            recording = true
            takeStarted = Date()
        } catch {
            message = "Microphone unavailable: \(error.localizedDescription)"
        }
    }

    /// Ends this take and starts the next one without stopping the microphone.
    private func nextTake() {
        keep(recorder.cut())
        takeStarted = Date()
    }

    private func finishTakes() {
        keep(recorder.stop())
        recording = false
        level = 0
    }

    /// The sentence to read for the take being recorded.
    private var currentSentence: String {
        let list = sentences.isEmpty ? VocabularyTrainer.builtInSentences(spelling) : sentences
        return list[takes.count % list.count]
    }

    /// Asks the LLM for sentences that fit the word (about 2 s); the built-in ones meanwhile, and if it can't.
    private func writeSentences() {
        guard TrainingSentences.available, !spelling.isEmpty else {
            sentences = VocabularyTrainer.builtInSentences(spelling)
            sentencesNote = "Built-in sentences. With an OpenRouter key (Setup), they're written to fit the word."
            return
        }
        writingSentences = true
        sentencesNote = nil
        let term = spelling, hint = hint
        let vocabulary = VocabularyStore.shared.entries.map(\.write)
        Task {
            do {
                let written = try await TrainingSentences.make(term: term, hint: hint, vocabulary: vocabulary)
                if written.count >= 3 {
                    sentences = written
                } else {
                    sentences = VocabularyTrainer.builtInSentences(term)
                    sentencesNote = "Couldn't write sentences that fit; using the built-in ones."
                }
            } catch {
                sentences = VocabularyTrainer.builtInSentences(term)
                sentencesNote = "Couldn't write sentences (\(error.localizedDescription)); using the built-in ones."
            }
            writingSentences = false
        }
    }

    /// The sentences you'll read: the next one marked; a hint and new ones on request.
    private var sentencesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                SectionLabel("You'll read")
                if writingSentences {
                    ProgressView().controlSize(.small)
                    Text("Writing sentences that fit “\(spelling)”…").font(VPFont.caption).foregroundStyle(Palette.fgMuted)
                }
                Spacer()
                if TrainingSentences.available {
                    Button("↻ New sentences") { writeSentences() }.buttonStyle(.vpGhost).disabled(writingSentences || recording || busy)
                }
            }
            if !writingSentences {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(sentences.enumerated()), id: \.offset) { i, sentence in
                        let next = i == takes.count % max(1, sentences.count)
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(i + 1)").font(VPFont.caption).monospacedDigit().foregroundStyle(Palette.comment).frame(width: 14, alignment: .trailing)
                            Text(sentence).font(VPFont.body).foregroundStyle(next ? Palette.fg : Palette.fgMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            if TrainingSentences.available {
                HStack(spacing: 8) {
                    VPTextField("What is it? (optional, e.g. terminal user interface)", text: $hint, onSubmit: writeSentences)
                        .frame(maxWidth: 380)
                    Text("Return writes new ones").font(VPFont.caption).foregroundStyle(Palette.comment)
                }
                .disabled(recording || busy)
            }
            if let sentencesNote { Text(sentencesNote).font(VPFont.caption).foregroundStyle(Palette.fgMuted) }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .vpCard()
    }

    private func keep(_ samples: [Float]) {
        let peak = samples.reduce(Float(0)) { max($0, abs($1)) }
        if samples.count < 4_800 {
            message = "That take was too short; it wasn't kept."
        } else if peak < 0.01 {
            message = "That take was silent — is the right microphone selected? It wasn't kept."
        } else {
            takes.append(VocabularyTrainer.Take(samples: samples, sentence: currentSentence))
            message = nil
        }
    }

    // MARK: - Training

    private func train() {
        phase = .transcribing
        report = nil
        verdicts = [:]
        message = nil
        let trainer = VocabularyTrainer(parakeet: parakeet, spelling: spelling)
        let takes = takes, useVoices = useVoices, target = spelling, sentences = sentences
        let started = Date()
        Task {
            let result = await trainer.run(takes: takes, sentences: sentences, useVoices: useVoices) { done, total in
                self.done = done
                self.total = total
            }
            trainedSeconds = Date().timeIntervalSince(started)
            if JevClient.hasKey, !result.results.isEmpty {
                phase = .judging
                do {
                    verdicts = try await JevClient.shared.judgeReplacements(target: target, candidates: result.results.map(\.text))
                } catch {
                    message = "\(error.localizedDescription) Falling back to the dictionary check."
                }
            }
            preselect(result)
            report = result
            phase = .idle
        }
    }

    /// With Jev: tick what it rates at `threshold` or more. Without: tick repeats that aren't all ordinary words.
    private func preselect(_ report: VocabularyTrainer.Report) {
        let existing = Set(entry.heardAs.map { $0.lowercased() })
        selected = Set(report.results.filter { r in
            guard !existing.contains(r.text) else { return false }
            if let p = verdicts[r.text] { return p >= threshold }
            return !r.commonWords && r.count >= 2
        }.map(\.text))
    }

    @ViewBuilder private func results(_ report: VocabularyTrainer.Report) -> some View {
        if !report.results.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                if !verdicts.isEmpty { thresholdRow(report) }
                HStack(spacing: 12) {
                    SectionLabel("How it came out")
                    Spacer()
                    SectionLabel("×").frame(width: 40, alignment: .trailing)
                    SectionLabel("Jev").frame(width: 56, alignment: .trailing)
                }
                ScrollView {
                    Card {
                        ForEach(Array(sortedResults(report).enumerated()), id: \.element.id) { index, result in
                            if index > 0 { Hairline() }
                            resultRow(result)
                        }
                    }
                }
                .frame(maxHeight: 340)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// "Tick everything Jev rates at least …": sets the ticks; you can change any of them after.
    private func thresholdRow(_ report: VocabularyTrainer.Report) -> some View {
        let binding = Binding { threshold } set: { threshold = ($0 * 20).rounded() / 20 }
        return HStack(spacing: 10) {
            Text("Tick what Jev rates at least").font(VPFont.caption).foregroundStyle(Palette.fgMuted)
            Slider(value: binding, in: 0.05...0.95).frame(width: 160)
                .accessibilityLabel("Threshold")
                .accessibilityValue("\(Int((threshold * 100).rounded())) percent")
            Text("\(Int((threshold * 100).rounded()))%").font(VPFont.bodyStrong).monospacedDigit().frame(width: 40, alignment: .trailing)
            Spacer()
            Text("\(selected.count) of \(report.results.count) ticked").font(VPFont.caption).monospacedDigit().foregroundStyle(Palette.fgMuted)
        }
        .padding(.bottom, 4)
        .onChange(of: threshold) { _, _ in preselect(report) }
    }

    /// The whole row is one button that ticks the result.
    private func resultRow(_ result: VocabularyTrainer.Result) -> some View {
        let on = selected.contains(result.text)
        return Button {
            if on { selected.remove(result.text) } else { selected.insert(result.text) }
        } label: {
            HStack(spacing: 12) {
                CheckboxMark(isOn: on)
                HStack(spacing: 0) {
                    Text(result.text).foregroundStyle(Palette.fg)
                    if result.commonWords {
                        Text(" · ordinary words").font(VPFont.caption).foregroundStyle(Palette.orange)
                    } else if result.count == 1 {
                        Text(" · once").font(VPFont.caption).foregroundStyle(Palette.fgMuted)
                    }
                }
                .lineLimit(1)
                Spacer()
                Text("\(result.count)").font(VPFont.caption).monospacedDigit().foregroundStyle(Palette.fgMuted)
                    .frame(width: 40, alignment: .trailing)
                Group {
                    if let p = verdicts[result.text] {
                        Text("\(Int((p * 100).rounded()))%")
                            .foregroundStyle(p >= threshold ? Palette.green : p >= threshold - 0.15 ? Palette.yellow : Palette.orange)
                    } else {
                        Text("—").foregroundStyle(Palette.comment)
                    }
                }
                .monospacedDigit()
                .frame(width: 56, alignment: .trailing)
            }
            .padding(.horizontal, 12).frame(minHeight: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(helpText(result))
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    private func helpText(_ result: VocabularyTrainer.Result) -> String {
        var text = source(result)
        if let p = verdicts[result.text] {
            text += p >= threshold ? ". Jev thinks this is a garbled version of the word: safe to replace."
                : ". Jev thinks this could be something people actually write, so replacing it could change text you meant."
        }
        return text
    }

    /// Most likely to be safe first when Jev has judged them; otherwise most frequent first.
    private func sortedResults(_ report: VocabularyTrainer.Report) -> [VocabularyTrainer.Result] {
        guard !verdicts.isEmpty else { return report.results }
        return report.results.sorted { (verdicts[$0.text] ?? 0, $0.count) > (verdicts[$1.text] ?? 0, $1.count) }
    }

    private func source(_ result: VocabularyTrainer.Result) -> String {
        switch (result.fromYou, result.fromVoices) {
        case (0, let v): "\(v)× voices"
        case (let y, 0): "\(y)× you"
        case (let y, let v): "\(y)× you · \(v)× voices"
        }
    }

    private func add() {
        var heard = entry.heardAs
        let existing = Set(heard.map { $0.lowercased() })
        for text in report?.results.map(\.text) ?? [] where selected.contains(text) && !existing.contains(text) {
            heard.append(text)
        }
        entry.heardAs = heard
        entry.heardAsText = nil
        dismiss()
    }
}

/// Eight bars showing the microphone level, so it's obvious a take is actually being heard.
private struct LevelBars: View {
    let level: Float

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<8, id: \.self) { i in
                Rectangle()
                    .fill(level > Float(i) / 8 ? Palette.green : Palette.bg300)
                    .frame(width: 3, height: 6 + CGFloat(i % 4) * 3)
            }
        }
    }
}

/// A thin progress bar: lavender on leather.
struct ProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).fill(Palette.bg300)
                RoundedRectangle(cornerRadius: 2).fill(Palette.purple).frame(width: geo.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: 4)
    }
}
