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

/// The Mac's microphones, by name (what config.toml and the pickers use; names survive reconnects and read well).
enum AudioInputs {
    /// `input = "system"`: whatever macOS has as its input (System Settings → Sound), following it when it changes.
    static let system = "system"

    struct Device: Hashable {
        let id: AudioDeviceID
        let name: String
        let bluetooth: Bool
    }

    /// Every device that can record, in the order macOS lists them.
    static func all() -> [Device] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            guard hasInput(id), let name = name(id) else { return nil }
            return Device(id: id, name: name, bluetooth: isBluetooth(id))
        }
    }

    /// The device a setting means now: a named mic if it's connected, otherwise the system's input.
    static func resolve(_ input: String) -> Device? {
        if input != system, let device = all().first(where: { $0.name == input }) { return device }
        return systemDevice()
    }

    /// Is a named mic connected? (`system` always is.)
    static func isConnected(_ input: String) -> Bool { input == system || all().contains { $0.name == input } }

    static func systemDevice() -> Device? {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr, id != 0,
              let name = name(id) else { return nil }
        return Device(id: id, name: name, bluetooth: isBluetooth(id))
    }

    /// "System (MacBook Pro Microphone)", or the mic's own name.
    static func label(_ input: String) -> String {
        guard input == system else { return isConnected(input) ? input : "\(input) (not connected)" }
        return systemDevice().map { "System (\($0.name))" } ?? "System"
    }

    private static func hasInput(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioDevicePropertyScopeInput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func name(_ id: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name) == noErr, let value = name?.takeRetainedValue() else { return nil }
        return value as String
    }

    private static func isBluetooth(_ id: AudioDeviceID) -> Bool {
        var transport = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &transport) == noErr else { return false }
        return transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
    }
}

/// Captures a microphone (`input`: the system's, or one by name) as 16 kHz mono Float32, the format Parakeet and the
/// cloud STT want. Between takes it can keep the microphone open (`readiness`), holding the last half second for the
/// next take.
final class AudioRecorder: @unchecked Sendable {
    static let sampleRate: Double = 16_000
    /// Audio from before the press that an open microphone adds to a take: you tend to start talking as you press.
    static let prerollSeconds = 0.5

    /// The open microphone (nil when closed).
    private var mic: HALInput?
    /// Guards `samples`, `preroll`, `capturing` and `lastBuffer` (the audio thread writes them), and keeps `onSamples`
    /// in order.
    private let lock = NSLock()
    private var samples: [Float] = []
    private var preroll: [Float] = []
    private var capturing = false
    /// When the microphone last delivered audio (system uptime).
    private var lastBuffer: TimeInterval = 0
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                                             channels: 1, interleaved: false)!
    // Main thread only.
    private var running = false
    private var coolDown: DispatchWorkItem?
    /// The device the engine records from, and the check that it still delivers audio.
    private var openDevice: AudioDeviceID?
    private var watchdog: Timer?
    /// Reopens in a row that didn't bring audio back; the watchdog gives up after a few (a device that's gone dead).
    private var silentReopens = 0
    private var deviceListener: AudioObjectPropertyListenerBlock?
    /// A running engine that's this long without audio has lost its device.
    private static let silentLimit: TimeInterval = 0.75

    /// Called on the audio thread with each converted block of a take (the preroll first, on the caller's thread).
    var onSamples: (@Sendable ([Float]) -> Void)?
    /// Normalized input level (0...1) for the HUD meter.
    var onLevel: (@Sendable (Float) -> Void)?

    /// What happens between takes. Off for recorders other than the app's own; set on the main thread.
    var readiness: MicReadiness = .off {
        didSet { if readiness != oldValue { settle() } }
    }

    /// `AudioInputs.system` or a mic's name. A named mic that isn't connected records from the system's input.
    let input: String

    init(input: String = AudioInputs.system) {
        self.input = input
        observeDevices()
    }

    deinit {
        watchdog?.invalidate()
        if let deviceListener {
            for var address in Self.deviceAddresses {
                AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, deviceListener)
            }
        }
    }

    func start() throws {
        coolDown?.cancel()
        coolDown = nil
        // An open microphone that's gone quiet (its device changed without telling the engine) is reopened, so this
        // take records. A live one delivers a buffer every ~20 ms.
        if running, lock.withLock({ ProcessInfo.processInfo.systemUptime - lastBuffer }) > Self.silentLimit { stopEngine() }
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
              AudioInputs.resolve(input)?.bluetooth != true else { return .off }
        return readiness
    }

    private func startEngine() throws {
        // A named mic that isn't connected resolves to the system's input.
        guard let device = AudioInputs.resolve(input) else { throw RecorderError.noFormat }
        let target = targetFormat
        var converter: AVAudioConverter?
        // Opening blocks while the device starts (~430 ms for the Studio Display mic).
        mic = try HALInput(device: device.id) { [weak self] buffer in
            // Audio thread. The converter follows the device's format (its own rate: a named mic needn't match the
            // system input's, e.g. AirPods in call mode at 24 kHz).
            if converter?.inputFormat != buffer.format { converter = AVAudioConverter(from: buffer.format, to: target) }
            guard let converter else { return }
            self?.process(buffer, converter)
        }
        lock.withLock { lastBuffer = ProcessInfo.processInfo.systemUptime }
        running = true
        openDevice = device.id
        startWatchdog()
    }

    /// Closes the microphone. `HALInput.stop()` returns once its last callback has run.
    private func stopEngine() {
        mic?.stop()
        mic = nil
        guard running else { return }
        running = false
        openDevice = nil
        watchdog?.invalidate()
        watchdog = nil
        lock.withLock { preroll.removeAll() }
    }

    /// While the microphone is open: when its device changes under it (a new sample rate, a headset switching modes)
    /// the engine often says nothing and simply stops delivering audio. Reopen it.
    private func startWatchdog() {
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self, self.running else { return }
            let silent = self.lock.withLock { ProcessInfo.processInfo.systemUptime - self.lastBuffer }
            guard silent > Self.silentLimit else { self.silentReopens = 0; return }
            guard self.silentReopens < 3 else { return }
            self.silentReopens += 1
            self.reopen("no audio for \(String(format: "%.1f", silent)) s")
        }
    }

    private static let deviceAddresses = [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice].map {
        AudioObjectPropertyAddress(mSelector: $0, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    /// Mics connecting and disconnecting, and the system's input changing: if the mic this recorder means is now a
    /// different device (a named mic came back, or went and the system's input stands in), reopen on it.
    private func observeDevices() {
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self, self.running, AudioInputs.resolve(self.input)?.id != self.openDevice else { return }
            self.reopen("microphone changed")
        }
        deviceListener = listener
        for var address in Self.deviceAddresses {
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
        }
    }

    /// Reopens on the current device, keeping the take in progress.
    private func reopen(_ reason: String) {
        NSLog("VoiceTools: reopening the microphone \(input) (\(reason))")
        stopEngine()
        restart()
    }

    /// Reopens the microphone after a device change, for the take in progress or to keep it open. A device that's
    /// just connected (or a headset switching to call mode) can take a moment to report a usable format.
    private func restart(attempt: Int = 1) {
        guard !running else { return }
        let inTake = lock.withLock { capturing }
        guard inTake || keepOpen != .off else { return }
        do {
            try startEngine()
            if !inTake { settle() }
        } catch {
            guard attempt < 5 else {
                NSLog("VoiceTools: microphone didn't restart after a device change: \(error)")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.restart(attempt: attempt + 1) }
        }
    }

    private func process(_ buffer: AVAudioPCMBuffer, _ converter: AVAudioConverter) {
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
            lastBuffer = ProcessInfo.processInfo.systemUptime
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

enum RecorderError: LocalizedError {
    case noFormat

    var errorDescription: String? {
        switch self {
        case .noFormat: "The microphone isn't ready (it may be connecting or switching). Try again in a moment."
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
