import SwiftUI

/// Record a word a few times, run every variation through Parakeet, and pick which mishearings to add.
struct TrainWordSheet: View {
    let parakeet: ParakeetService
    @Binding var entry: VocabularyEntry
    @Environment(\.dismiss) private var dismiss

    @State private var recorder = AudioRecorder()
    @State private var takes: [[Float]] = []
    @State private var recording = false
    @State private var useVoices = true
    @State private var running = false
    @State private var done = 0
    @State private var total = 0
    @State private var report: VocabularyTrainer.Report?
    @State private var selected: Set<String> = []
    @State private var error: String?

    private var spelling: String { entry.write.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Train “\(spelling)”").font(.title3.weight(.semibold))
            Text("Record yourself saying it a few times, on its own. Vary it a little between takes — quicker, slower, the way you'd say it mid-sentence. Each take is replayed about 30 ways (speed, volume, background noise) through Parakeet, and every distinct result is listed for you to pick from.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button { recording ? stopTake() : startTake() } label: {
                    Label(recording ? "Stop" : "Record take \(takes.count + 1)",
                          systemImage: recording ? "stop.circle.fill" : "mic.circle")
                }
                .controlSize(.large)
                .disabled(running)
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
            if takes.count < 3, !recording {
                Text(takes.isEmpty ? "Five takes works well." : "\(5 - takes.count) more takes would help.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Toggle("Also have on-device voices say it (Pocket TTS and Supertonic, 36 voices at two speeds)", isOn: $useVoices)
                .disabled(running)

            HStack {
                Button("Train") { train() }
                    .buttonStyle(.borderedProminent)
                    .disabled(running || recording || spelling.isEmpty || (takes.isEmpty && !useVoices))
                if running {
                    ProgressView(value: Double(done), total: Double(max(total, 1))).frame(width: 220)
                    Text("\(done) / \(total)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Spacer()
            }
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }

            if let report { results(report) }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add \(selected.count) to Heard as") { add() }
                    .buttonStyle(.borderedProminent)
                    .disabled(selected.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 620)
        .frame(minHeight: 300)
        .onDisappear { if recording { _ = recorder.stop() } }
    }

    @ViewBuilder private func results(_ report: VocabularyTrainer.Report) -> some View {
        let rate = report.total > 0 ? Int(Double(report.correct) / Double(report.total) * 100) : 0
        Text("Parakeet got it right \(report.correct) of \(report.total) times (\(rate)%). \(report.results.count) other ways it came out:")
            .font(.callout)
        if report.results.isEmpty {
            Text("Nothing else — it's already reliable.").foregroundStyle(.secondary)
        } else {
            List(report.results) { result in
                HStack {
                    Toggle(isOn: Binding {
                        selected.contains(result.text)
                    } set: { on in
                        if on { selected.insert(result.text) } else { selected.remove(result.text) }
                    }) {
                        Text(result.text)
                    }
                    Spacer()
                    if result.commonWords {
                        Label("ordinary words", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(.orange)
                            .help("Every word here is a normal dictionary word, so adding it would also replace them when you mean them literally.")
                    }
                    Text(source(result)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 180, maxHeight: 320)
        }
    }

    private func source(_ result: VocabularyTrainer.Result) -> String {
        switch (result.fromYou, result.fromVoices) {
        case (0, let v): "\(v)× voices"
        case (let y, 0): "\(y)× you"
        case (let y, let v): "\(y)× you · \(v)× voices"
        }
    }

    private func startTake() {
        error = nil
        do {
            try recorder.start()
            recording = true
            // Names are short; stop by itself after a few seconds.
            Task {
                try? await Task.sleep(for: .seconds(5))
                if recording { stopTake() }
            }
        } catch {
            self.error = "Microphone unavailable: \(error.localizedDescription)"
        }
    }

    private func stopTake() {
        let samples = recorder.stop()
        recording = false
        if samples.count > 4_800 { takes.append(samples) } else { error = "That take was too short." }
    }

    private func train() {
        running = true
        report = nil
        error = nil
        let trainer = VocabularyTrainer(parakeet: parakeet, spelling: spelling)
        let takes = takes, useVoices = useVoices
        Task {
            let result = await trainer.run(takes: takes, useVoices: useVoices) { done, total in
                self.done = done
                self.total = total
            }
            let existing = Set(entry.heardAs.map { $0.lowercased() })
            report = result
            // Pre-tick what came up at least twice, unless it's ordinary words; one-offs are listed but unticked.
            selected = Set(result.results.filter { r in
                !r.commonWords && !existing.contains(r.text) && r.count >= 2
            }.map(\.text))
            running = false
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
