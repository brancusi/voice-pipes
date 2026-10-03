import Foundation

/// Turns whatever a speech provider sends back into data `AVAudioPlayer` can play. Containers (MP3, WAV, AAC,
/// FLAC, CAF…) pass through; raw PCM, which has no header, is wrapped in a WAV header.
enum SpeechAudio {
    /// OpenRouter labels raw audio `audio/pcm;rate=24000;channels=1`: signed 16-bit little-endian samples.
    static func playable(_ data: Data, contentType: String?) -> Data {
        let type = contentType?.lowercased() ?? ""
        let rawPCM = type.contains("pcm") || type.contains("l16") || (!type.hasPrefix("audio/") && !hasContainer(data))
        guard rawPCM else { return data }
        let params = parameters(type)
        return wav(pcm: data,
                   sampleRate: params["rate"].flatMap(Int.init) ?? 24_000,
                   channels: params["channels"].flatMap(Int.init) ?? 1,
                   bitsPerSample: params["bits"].flatMap(Int.init) ?? 16)
    }

    /// `audio/pcm;rate=24000;channels=1` → ["rate": "24000", "channels": "1"].
    private static func parameters(_ contentType: String) -> [String: String] {
        var result: [String: String] = [:]
        for part in contentType.split(separator: ";").dropFirst() {
            let pair = part.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if pair.count == 2 { result[pair[0]] = pair[1] }
        }
        return result
    }

    /// Known file signatures: ID3 or an MPEG frame (MP3/AAC ADTS), RIFF (WAV), fLaC, OggS, caff, or an MP4 `ftyp` box.
    private static func hasContainer(_ data: Data) -> Bool {
        let b = [UInt8](data.prefix(12))
        guard b.count >= 4 else { return false }
        func ascii(_ s: String, at offset: Int = 0) -> Bool {
            b.count >= offset + s.utf8.count && Array(b[offset..<offset + s.utf8.count]) == Array(s.utf8)
        }
        return ascii("ID3") || (b[0] == 0xFF && b[1] & 0xE0 == 0xE0) || ascii("RIFF") || ascii("fLaC")
            || ascii("OggS") || ascii("caff") || ascii("ftyp", at: 4)
    }

    static func wav(pcm: Data, sampleRate: Int, channels: Int, bitsPerSample: Int) -> Data {
        var header = Data()
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { header.append(contentsOf: $0) } }
        let blockAlign = channels * bitsPerSample / 8
        header.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + pcm.count))
        header.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16))
        append(UInt16(1))  // integer PCM
        append(UInt16(channels))
        append(UInt32(sampleRate))
        append(UInt32(sampleRate * blockAlign))
        append(UInt16(blockAlign))
        append(UInt16(bitsPerSample))
        header.append(contentsOf: Array("data".utf8))
        append(UInt32(pcm.count))
        return header + pcm
    }
}
