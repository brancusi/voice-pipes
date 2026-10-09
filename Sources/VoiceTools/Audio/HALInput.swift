import AudioToolbox
@preconcurrency import AVFoundation
import CoreAudio

/// One microphone, opened input-only through Core Audio's HAL unit. AVAudioEngine runs input and output as one unit on
/// macOS, so a headset switching modes on the output side (AirPods going in and out of call mode) stalled a mic on a
/// different device, and dropping an engine mid-change crashed in its own listener. This unit never touches output.
final class HALInput {
    /// The device's format (Float32, its own rate and channels; the HAL unit can't convert rates).
    let format: AVAudioFormat
    private let unit: AudioUnit
    private let buffer: AVAudioPCMBuffer
    private let onBuffer: (AVAudioPCMBuffer) -> Void
    private var stopped = false

    /// Opens and starts `device`. Throws if it has no usable format right now (connecting, or switching modes).
    init(device: AudioDeviceID, onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws {
        let (unit, format) = try Self.open(device)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: Self.maxFrames(unit)) else {
            AudioComponentInstanceDispose(unit)
            throw RecorderError.noFormat
        }
        self.unit = unit
        self.format = format
        self.buffer = buffer
        self.onBuffer = onBuffer
        // Fully initialized from here, so a throw runs deinit, which releases the unit.
        var callback = AURenderCallbackStruct(inputProc: { refCon, flags, time, bus, frames, _ in
            Unmanaged<HALInput>.fromOpaque(refCon).takeUnretainedValue().render(flags, time, bus, frames)
        }, inputProcRefCon: Unmanaged.passUnretained(self).toOpaque())
        try Self.check("callback", AudioUnitSetProperty(unit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0,
                                                        &callback, UInt32(MemoryLayout<AURenderCallbackStruct>.size)))
        try Self.check("initialize", AudioUnitInitialize(unit))
        try Self.check("start", AudioOutputUnitStart(unit))
    }

    deinit { stop() }

    /// Stops the device (synchronously: no callback runs after this returns) and releases the unit.
    func stop() {
        guard !stopped else { return }
        stopped = true
        AudioOutputUnitStop(unit)
        AudioUnitUninitialize(unit)
        AudioComponentInstanceDispose(unit)
    }

    /// An input-only HAL unit on `device`, delivering Float32 at the device's rate and channel count.
    private static func open(_ device: AudioDeviceID) throws -> (AudioUnit, AVAudioFormat) {
        var description = AudioComponentDescription(componentType: kAudioUnitType_Output, componentSubType: kAudioUnitSubType_HALOutput,
                                                    componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0,
                                                    componentFlagsMask: 0)
        guard let component = AudioComponentFindNext(nil, &description) else { throw HALError.status("find", -1) }
        var made: AudioUnit?
        try check("new", AudioComponentInstanceNew(component, &made))
        guard let unit = made else { throw HALError.status("new", -1) }
        do {
            var on: UInt32 = 1, off: UInt32 = 0
            try check("input", AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &on, 4))
            try check("output", AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &off, 4))
            var device = device
            try check("device", AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &device,
                                                     UInt32(MemoryLayout<AudioDeviceID>.size)))
            var hardware = AudioStreamBasicDescription()
            var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            try check("format", AudioUnitGetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 1, &hardware, &size))
            // Mid-change (a headset connecting, or switching to call mode) a device can report no channels or 0 Hz.
            guard hardware.mSampleRate > 0, hardware.mChannelsPerFrame > 0,
                  let format = AVAudioFormat(standardFormatWithSampleRate: hardware.mSampleRate, channels: hardware.mChannelsPerFrame)
            else { throw RecorderError.noFormat }
            var client = format.streamDescription.pointee
            try check("client", AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &client,
                                                     UInt32(MemoryLayout<AudioStreamBasicDescription>.size)))
            return (unit, format)
        } catch {
            AudioComponentInstanceDispose(unit)
            throw error
        }
    }

    private static func maxFrames(_ unit: AudioUnit) -> AVAudioFrameCount {
        var frames: UInt32 = 0
        var size = UInt32(4)
        AudioUnitGetProperty(unit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &frames, &size)
        return max(frames, 4096)
    }

    private func render(_ flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>, _ time: UnsafePointer<AudioTimeStamp>,
                        _ bus: UInt32, _ frames: UInt32) -> OSStatus {
        guard frames <= buffer.frameCapacity else { return noErr }
        buffer.frameLength = frames
        let list = buffer.mutableAudioBufferList
        let abl = UnsafeMutableAudioBufferListPointer(list)
        for i in 0..<abl.count { abl[i].mDataByteSize = frames * UInt32(MemoryLayout<Float>.size) }
        let status = AudioUnitRender(unit, flags, time, bus, frames, list)
        if status == noErr { onBuffer(buffer) }
        return status
    }

    private static func check(_ step: String, _ status: OSStatus) throws {
        guard status == noErr else { throw HALError.status(step, status) }
    }
}

enum HALError: LocalizedError {
    case status(String, OSStatus)

    var errorDescription: String? {
        switch self {
        case .status(let step, let status): "The microphone couldn't open (\(step): \(status))."
        }
    }
}
