@preconcurrency import AVFoundation
import CoreAudio

/// Whether the microphone stays open between takes ([settings] microphone). Starting a mic takes 150–550 ms
/// (the Studio Display's ~430 ms is the slow one), and the first word was lost in that gap. An open mic starts a take
/// at once and keeps the half second before the press. macOS shows its orange mic dot while it's open.
enum MicReadiness: String, CaseIterable, Identifiable, Sendable {
    /// Open from launch.
    case always
    /// Open for a few minutes after each take; the first take after a quiet spell starts cold.
    case afterUse = "after-use"
    /// Opened for each take, as before 1.8.3.
    case off

    /// How long `afterUse` keeps it open.
    static let afterUseSeconds: TimeInterval = 300

    var id: String { rawValue }

    var label: String {
        switch self {
        case .always: "Always"
        case .afterUse: "After use"
        case .off: "Off"
        }
    }

    var detail: String {
        switch self {
        case .always: "The microphone stays open, so a take starts instantly and keeps the half second before you pressed. macOS shows the orange mic dot the whole time. The audio stays in memory until you press, and is never saved."
        case .afterUse: "The microphone stays open for 5 minutes after each take, so the next one starts instantly. The first take after a quiet spell can miss its first half second."
        case .off: "The microphone opens when you press. Depending on the mic, the first 0.15–0.5 s can be cut off."
        }
    }
}

/// Captures the default microphone as 16 kHz mono Float32, the format Parakeet and the cloud STT want.
/// Between takes it can keep the microphone open (`readiness`), holding the last half second for the next take.
final class AudioRecorder: @unchecked Sendable {
    static let sampleRate: Double = 16_000
    /// Audio from before the press that an open microphone adds to a take: you tend to start talking as you press.
    static let prerollSeconds = 0.5

    private var engine = AVAudioEngine()
    /// Guards `samples`, `preroll` and `capturing` (the audio thread writes them), and keeps `onSamples` in order.
    private let lock = NSLock()
    private var samples: [Float] = []
    private var preroll: [Float] = []
    private var capturing = false
    private var converter: AVAudioConverter?
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                                             channels: 1, interleaved: false)!
    // Main thread only.
    private var running = false
    private var coolDown: DispatchWorkItem?
    private var configObserver: NSObjectProtocol?

    /// Called on the audio thread with each converted block of a take (the preroll first, on the caller's thread).
    var onSamples: (@Sendable ([Float]) -> Void)?
    /// Normalized input level (0...1) for the HUD meter.
    var onLevel: (@Sendable (Float) -> Void)?

    /// What happens between takes. Off for recorders other than the app's own; set on the main thread.
    var readiness: MicReadiness = .off {
        didSet { if readiness != oldValue { settle() } }
    }

    init() { observeConfiguration() }

    deinit {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
    }

    func start() throws {
        coolDown?.cancel()
        coolDown = nil
        if !running { try startEngine() }
        lock.withLock {
            let keep = Int(Self.sampleRate * Self.prerollSeconds)
            samples = Array(preroll.suffix(keep))
            preroll.removeAll(keepingCapacity: true)
            capturing = true
            if !samples.isEmpty { onSamples?(samples) }
        }
    }

    /// Returns what's been recorded since the last cut and keeps recording (for back-to-back takes).
    func cut() -> [Float] {
        lock.withLock {
            let taken = samples
            samples.removeAll(keepingCapacity: true)
            return taken
        }
    }

    /// Ends the take and returns everything recorded. The microphone stays open if `readiness` says so.
    func stop() -> [Float] {
        let taken = lock.withLock {
            capturing = false
            let taken = samples
            samples = []
            return taken
        }
        settle()
        return taken
    }

    // MARK: Engine

    /// Opens or closes the microphone to match `readiness` (between takes; a take in progress is left alone).
    private func settle() {
        guard !lock.withLock({ capturing }) else { return }
        coolDown?.cancel()
        coolDown = nil
        switch keepOpen {
        case .always:
            if !running { try? startEngine() }
        case .afterUse:
            guard running else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self, !self.lock.withLock({ self.capturing }) else { return }
                self.coolDown = nil
                self.stopEngine()
            }
            coolDown = work
            DispatchQueue.main.asyncAfter(deadline: .now() + MicReadiness.afterUseSeconds, execute: work)
        case .off:
            stopEngine()
        }
    }

    /// `readiness`, except that a Bluetooth microphone is never kept open: an open Bluetooth mic holds the headset in
    /// call mode, which makes everything it plays sound like a phone call. And nothing opens without permission.
    private var keepOpen: MicReadiness {
        guard readiness != .off, AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
              !Self.defaultInputIsBluetooth() else { return .off }
        return readiness
    }

    private func startEngine() throws {
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.process(buffer)
        }
        engine.prepare()
        try engine.start()
        running = true
    }

    private func stopEngine() {
        guard running else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        running = false
        lock.withLock { preroll.removeAll() }
    }

    /// The default input changed (a headset, a display, sleep): the engine has stopped. Start a fresh one on the new
    /// device if a take is running or the microphone should stay open.
    private func observeConfiguration() {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine,
                                                                queue: .main) { [weak self] _ in
            self?.configurationChanged()
        }
    }

    private func configurationChanged() {
        let wasRunning = running
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        running = false
        lock.withLock { preroll.removeAll() }
        engine = AVAudioEngine()
        observeConfiguration()
        guard wasRunning else { return }
        if lock.withLock({ capturing }) {
            do { try startEngine() } catch { NSLog("VoiceTools: microphone didn't restart after a device change: \(error)") }
        } else if keepOpen != .off {
            try? startEngine()
            settle()
        }
    }

    private static func defaultInputIsBluetooth() -> Bool {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr else { return false }
        var transport = UInt32(0)
        size = UInt32(MemoryLayout<UInt32>.size)
        address.mSelector = kAudioDevicePropertyTransportType
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport) == noErr else { return false }
        return transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
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

        let inTake = lock.withLock {
            guard capturing else {
                // Between takes: keep only the last half second or so.
                preroll.append(contentsOf: block)
                let keep = Int(Self.sampleRate * Self.prerollSeconds)
                if preroll.count > keep * 2 { preroll.removeFirst(preroll.count - keep) }
                return false
            }
            samples.append(contentsOf: block)
            onSamples?(block)
            return true
        }
        if inTake, let onLevel {
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
