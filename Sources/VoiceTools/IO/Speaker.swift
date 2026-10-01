import AVFoundation
import Observation

/// Read-aloud playback that can pause and resume at the exact word, and reports progress for the UI.
@MainActor
@Observable
final class Speaker: NSObject {
    enum State { case idle, speaking, paused }

    private(set) var state: State = .idle
    private(set) var text = ""
    private(set) var spokenRange = NSRange(location: 0, length: 0)
    private(set) var sourceLabel = ""

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var finished: CheckedContinuation<Void, Never>?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    var progress: Double {
        text.isEmpty ? 0 : Double(spokenRange.location + spokenRange.length) / Double((text as NSString).length)
    }

    /// Speaks and returns when playback finishes or is cleared.
    func speak(_ text: String, voiceID: String?, rate: Float, label: String) async {
        clear()
        self.text = text
        sourceLabel = label
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voiceID.flatMap(AVSpeechSynthesisVoice.init(identifier:)) ?? Self.bestDefaultVoice
        utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * rate)
        state = .speaking
        synthesizer.speak(utterance)
        await withCheckedContinuation { finished = $0 }
    }

    func togglePause() {
        switch state {
        case .speaking:
            synthesizer.pauseSpeaking(at: .word)
            state = .paused
        case .paused:
            synthesizer.continueSpeaking()
            state = .speaking
        case .idle:
            break
        }
    }

    func clear() {
        synthesizer.stopSpeaking(at: .immediate)
        finish()
        text = ""
        spokenRange = NSRange(location: 0, length: 0)
    }

    private func finish() {
        state = .idle
        finished?.resume()
        finished = nil
    }

    /// Highest-quality installed voice for the user's language.
    static var bestDefaultVoice: AVSpeechSynthesisVoice? {
        let language = AVSpeechSynthesisVoice.currentLanguageCode()
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == language }
            .max { $0.quality.rawValue < $1.quality.rawValue }
            ?? AVSpeechSynthesisVoice(language: language)
    }
}

extension Speaker: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString range: NSRange,
                                       utterance: AVSpeechUtterance) {
        Task { @MainActor in self.spokenRange = range }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finish() }
    }
}
