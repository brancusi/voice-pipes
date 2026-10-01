import SwiftUI

/// Record a word several times back to back, run every variation through Parakeet, have Jev judge which
/// mishearings are safe to replace, and pick which to add.
struct TrainWordSheet: View {
    let parakeet: ParakeetService
    @Binding var entry: VocabularyEntry
    @Environment(\.dismiss) private var dismiss

    @State private var recorder = AudioRecorder()
    @State private var takes: [[Float]] = []
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

    private enum Phase { case idle, transcribing, judging }
    private var spelling: String { entry.write.trimmingCharacters(in: .whitespaces) }
    private var busy: Bool { phase != .idle }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Train “\(spelling)”").font(.title3.weight(.semibold))
            Text("Click **Start takes** and say it; click **Next take** and say it again — about five times, varying it a little. Each take is replayed about 30 ways (speed, volume, background noise) through Parakeet. \(JevClient.hasKey ? "Jev then judges which results are safe to replace everywhere." : "Add a Jev key in Setup to have each result judged automatically.")")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            recordingControls

            Toggle("Also have on-device voices say it (Pocket TTS and Supertonic, 36 voices at two speeds)", isOn: $useVoices)
                .disabled(busy)

            HStack {
                Button("Train") { train() }
                    .buttonStyle(.borderedProminent)
                    .disabled(busy || recording || spelling.isEmpty || (takes.isEmpty && !useVoices))
                switch phase {
                case .transcribing:
                    ProgressView(value: Double(done), total: Double(max(total, 1))).frame(width: 200)
                    Text("\(done) / \(total)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                case .judging:
                    ProgressView().controlSize(.small)
                    Text("Asking Jev…").font(.caption).foregroundStyle(.secondary)
                case .idle:
                    EmptyView()
                }
                Spacer()
            }
            if let message { Text(message).font(.caption).foregroundStyle(.orange) }

            if let report { results(report) }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add \(selected.count) to Heard as") { add() }
                    .buttonStyle(.borderedProminent)
                    .disabled(selected.isEmpty || busy)
            }
        }
        .padding(20)
        .frame(width: 640)
        .frame(minHeight: 300)
        .onDisappear { if recording { _ = recorder.stop() } }
    }

    // MARK: - Recording

    private var recordingControls: some View {
        HStack(spacing: 10) {
            if recording {
                Circle().fill(.red).frame(width: 9, height: 9)
                Text("Take \(takes.count + 1)").font(.callout.monospacedDigit())
                LevelBars(level: level)
                TimelineView(.periodic(from: takeStarted, by: 0.1)) { context in
                    Text(String(format: "%.1fs", context.date.timeIntervalSince(takeStarted)))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Button("Next take") { nextTake() }.keyboardShortcut(.space, modifiers: [])
                Button("Finish") { finishTakes() }.keyboardShortcut(.return, modifiers: [])
            } else {
                Button { startTakes() } label: { Label(takes.isEmpty ? "Start takes" : "Record more takes", systemImage: "mic.circle") }
                    .controlSize(.large)
                    .disabled(busy)
                ForEach(takes.indices, id: \.self) { i in
                    HStack(spacing: 4) {
                        Text("\(i + 1) · \(String(format: "%.1f", Double(takes[i].count) / 16_000))s")
                        Button { takes.remove(at: i) } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.borderless)
                    }
                    .font(.caption.monospacedDigit())
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                }
            }
            Spacer()
        }
        .frame(minHeight: 30)
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

    private func keep(_ samples: [Float]) {
        let peak = samples.reduce(Float(0)) { max($0, abs($1)) }
        if samples.count < 4_800 {
            message = "That take was too short; it wasn't kept."
        } else if peak < 0.01 {
            message = "That take was silent — is the right microphone selected? It wasn't kept."
        } else {
            takes.append(samples)
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
        let takes = takes, useVoices = useVoices, target = spelling
        Task {
            let result = await trainer.run(takes: takes, useVoices: useVoices) { done, total in
                self.done = done
                self.total = total
            }
            report = result
            if JevClient.hasKey, !result.results.isEmpty {
                phase = .judging
                do {
                    verdicts = try await JevClient.shared.judgeReplacements(target: target, candidates: result.results.map(\.text))
                } catch {
                    message = "\(error.localizedDescription) Falling back to the dictionary check."
                }
            }
            preselect(result)
            phase = .idle
        }
    }

    /// With Jev: tick what it judges safe (60%+). Without: tick repeats that aren't all ordinary words.
    private func preselect(_ report: VocabularyTrainer.Report) {
        let existing = Set(entry.heardAs.map { $0.lowercased() })
        selected = Set(report.results.filter { r in
            guard !existing.contains(r.text) else { return false }
            if let p = verdicts[r.text] { return p >= 0.6 }
            return !r.commonWords && r.count >= 2
        }.map(\.text))
    }

    @ViewBuilder private func results(_ report: VocabularyTrainer.Report) -> some View {
        let rate = report.total > 0 ? Int(Double(report.correct) / Double(report.total) * 100) : 0
        Text("Parakeet got it right \(report.correct) of \(report.total) times (\(rate)%). \(report.results.count) other ways it came out:")
            .font(.callout)
        if report.results.isEmpty {
            Text("Nothing else — it's already reliable.").foregroundStyle(.secondary)
        } else {
            List(sortedResults(report)) { result in
                HStack {
                    Toggle(isOn: Binding {
                        selected.contains(result.text)
                    } set: { on in
                        if on { selected.insert(result.text) } else { selected.remove(result.text) }
                    }) {
                        Text(result.text)
                    }
                    Spacer()
                    if let p = verdicts[result.text] {
                        Text("Jev \(Int((p * 100).rounded()))%")
                            .font(.caption.monospacedDigit().weight(.medium))
                            .foregroundStyle(p >= 0.6 ? .green : p >= 0.35 ? .orange : .red)
                            .help(p >= 0.6 ? "Jev thinks this is a garbled version of the word: safe to replace."
                                  : "Jev thinks this could be something people actually write, so replacing it could change text you meant.")
                    } else if result.commonWords {
                        Label("ordinary words", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    Text(source(result)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        .frame(width: 110, alignment: .trailing)
                }
            }
            .frame(minHeight: 200, maxHeight: 340)
        }
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

/// Five bars showing the microphone level, so it's obvious a take is actually being heard.
private struct LevelBars: View {
    let level: Float

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<8, id: \.self) { i in
                Capsule()
                    .fill(level > Float(i) / 8 ? Color.green : Color.primary.opacity(0.15))
                    .frame(width: 3, height: 6 + CGFloat(i % 4) * 3)
            }
        }
    }
}
