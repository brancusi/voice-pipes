@preconcurrency import AVFoundation
import CoreAudio

/// Records a voiceover take at the microphone's own rate, mono (its first channel), untouched: what's written to the
/// file. A 16 kHz copy goes to live transcription and the level to the HUD's meter. Its own input unit, beside the
/// app's recorder, so the dictation microphone's settings don't apply.
final class VoiceoverRecorder: @unchecked Sendable {
    private var mic: HALInput?
    private let lock = NSLock()
    private var native: [Float] = []
    private var speech: [Float] = []
    private var capturing = false
    private(set) var sampleRate: Double = 48_000
    private(set) var deviceName: String?
    private let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: AudioRecorder.sampleRate,
                                       channels: 1, interleaved: false)!

    /// 0…1, while open (audio thread): the meter moves during the countdown too.
    var onLevel: (@Sendable (Float) -> Void)?

    /// Opens the microphone (the countdown runs while it wakes); nothing is kept until `record()`.
    func open(input: String) throws {
        guard mic == nil else { return }
        guard let device = AudioInputs.resolve(input) else { throw RecorderError.noFormat }
        var converter: AVAudioConverter?
        let target = target
        mic = try HALInput(device: device.id) { [weak self] buffer in
            if converter?.inputFormat != buffer.format { converter = AVAudioConverter(from: buffer.format, to: target) }
            self?.process(buffer, converter)
        }
        sampleRate = mic?.format.sampleRate ?? 48_000
        deviceName = device.name
    }

    func record() { lock.withLock { capturing = true } }

    /// Stops keeping audio (the microphone stays open for a retake until `close()`).
    func pause() { lock.withLock { capturing = false } }

    func close() {
        pause()
        mic?.stop()
        mic = nil
    }

    /// The take so far: at the microphone's rate, and at 16 kHz.
    var take: (native: [Float], speech: [Float]) { lock.withLock { (native, speech) } }

    /// The last `seconds` of the take at 16 kHz, for following the reader.
    func recentSpeech(_ seconds: Double) -> [Float] {
        lock.withLock { Array(speech.suffix(Int(seconds * AudioRecorder.sampleRate))) }
    }

    /// Keeps the first `seconds` of the take (a retake from a sentence), or none of it.
    func truncate(to seconds: Double) {
        lock.withLock {
            native = Array(native.prefix(max(0, Int(seconds * sampleRate))))
            speech = Array(speech.prefix(max(0, Int(seconds * AudioRecorder.sampleRate))))
        }
    }

    private func process(_ buffer: AVAudioPCMBuffer, _ converter: AVAudioConverter?) {
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
        let block = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        let rms = sqrt(block.reduce(0) { $0 + $1 * $1 } / Float(block.count))
        onLevel?(min(1, rms * 12))
        guard lock.withLock({ capturing }), let converter else { return }

        let ratio = target.sampleRate / buffer.format.sampleRate
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32)
        else { return }
        var consumed = false
        converter.convert(to: out, error: nil) { _, status in
            if consumed { status.pointee = .noDataNow; return nil }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        let small = out.floatChannelData.map { Array(UnsafeBufferPointer(start: $0[0], count: Int(out.frameLength))) } ?? []
        lock.withLock {
            native.append(contentsOf: block)
            speech.append(contentsOf: small)
        }
    }

    /// Writes mono samples untouched: WAV as 24-bit PCM, `.m4a`/`.caf` as Apple Lossless.
    static func write(_ samples: [Float], sampleRate: Double, to url: URL) throws {
        let lossless = ["m4a", "caf"].contains(url.pathExtension.lowercased())
        let settings: [String: Any] = [
            AVFormatIDKey: lossless ? kAudioFormatAppleLossless : kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            lossless ? AVEncoderBitDepthHintKey : AVLinearPCMBitDepthKey: 24,
        ].merging(lossless ? [:] : [AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]) { a, _ in a }
        try? FileManager.default.removeItem(at: url)
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let chunk = 1 << 16
        var at = 0
        while at < samples.count {
            let count = min(chunk, samples.count - at)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)) else { break }
            buffer.frameLength = AVAudioFrameCount(count)
            samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress! + at, count: count) }
            try file.write(from: buffer)
            at += count
        }
    }
}
