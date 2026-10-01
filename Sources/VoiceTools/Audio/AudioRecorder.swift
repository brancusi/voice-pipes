@preconcurrency import AVFoundation

/// Captures the default microphone as 16 kHz mono Float32, the format Parakeet and the cloud STT want.
final class AudioRecorder: @unchecked Sendable {
    static let sampleRate: Double = 16_000

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var samples: [Float] = []
    private var converter: AVAudioConverter?
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                                             channels: 1, interleaved: false)!

    /// Called on the audio thread with each converted block.
    var onSamples: (@Sendable ([Float]) -> Void)?
    /// Normalized input level (0...1) for the HUD meter.
    var onLevel: (@Sendable (Float) -> Void)?

    func start() throws {
        lock.withLock { samples.removeAll(keepingCapacity: true) }
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.process(buffer)
        }
        engine.prepare()
        try engine.start()
    }

    /// Stops capture and returns everything recorded.
    func stop() -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        return lock.withLock { samples }
    }

    private func process(_ buffer: AVAudioPCMBuffer) {
        guard let converter else { return }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var consumed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let channel = out.floatChannelData?[0], out.frameLength > 0 else { return }
        let block = Array(UnsafeBufferPointer(start: channel, count: Int(out.frameLength)))

        lock.withLock { samples.append(contentsOf: block) }
        onSamples?(block)
        if let onLevel {
            let rms = sqrt(block.reduce(0) { $0 + $1 * $1 } / Float(block.count))
            onLevel(min(1, rms * 12))
        }
    }
}

enum WAV {
    /// Encodes 16 kHz mono float samples as a 16-bit PCM WAV file.
    static func encode(_ samples: [Float], sampleRate: Int = 16_000) -> Data {
        var data = Data(capacity: 44 + samples.count * 2)
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        let byteCount = UInt32(samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8)); append(36 + byteCount)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(sampleRate)); append(UInt32(sampleRate * 2)); append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); append(byteCount)
        for s in samples { append(Int16(max(-1, min(1, s)) * Float(Int16.max))) }
        return data
    }
}
