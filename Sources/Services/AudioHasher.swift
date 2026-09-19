import Foundation
import AVFoundation
import CryptoKit
import CoreMedia

// SHA-256 ueber dekodierte PCM-Frames (nicht die Datei), Dauer als zweites Kriterium (Spec 13.3).
// Primaer AVAssetReader (dekodiert mp3/m4a/wav/aif zuverlaessig), FLAC ueber AVAudioFile.
enum AudioHasher {
    struct Result { let hash: String; let duration: Double }

    static var lastError: String = ""

    static func hash(url: URL) async -> Result? {
        if url.pathExtension.lowercased() == "flac" {
            return hashWithAudioFile(url: url)
        }
        if let result = await hashWithAssetReader(url: url) { return result }
        return hashWithAudioFile(url: url)
    }

    private static func hashWithAssetReader(url: URL) async -> Result? {
        let asset = AVURLAsset(url: url)
        guard let tracks = try? await asset.loadTracks(withMediaType: .audio), let track = tracks.first else {
            lastError = "kein Audio-Track"
            return nil
        }
        guard let reader = try? AVAssetReader(asset: asset) else {
            lastError = "AVAssetReader init"
            return nil
        }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        guard reader.canAdd(output) else { lastError = "Cannot create output"; return nil }
        reader.add(output)
        guard reader.startReading() else { lastError = "Could not start reading"; return nil }
        var hasher = SHA256()
        while let sample = output.copyNextSampleBuffer() {
            if let block = CMSampleBufferGetDataBuffer(sample) {
                var length = 0
                var pointer: UnsafeMutablePointer<Int8>?
                if CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &pointer) == noErr,
                   let pointer {
                    hasher.update(bufferPointer: UnsafeRawBufferPointer(start: pointer, count: length))
                }
            }
        }
        guard reader.status != .failed else {
            lastError = "reader failed: \(reader.error?.localizedDescription ?? "?")"
            return nil
        }
        let seconds = (try? await asset.load(.duration).seconds) ?? 0
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return Result(hash: digest, duration: seconds)
    }

    private static func hashWithAudioFile(url: URL) -> Result? {
        guard let file = try? AVAudioFile(forReading: url) else {
            lastError = "Could not open audio file"
            return nil
        }
        let format = file.processingFormat
        let duration = Double(file.length) / max(1, format.sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 65_536) else {
            lastError = "Could not allocate audio buffer"
            return nil
        }
        var hasher = SHA256()
        do {
            while file.framePosition < file.length {
                try file.read(into: buffer, frameCount: 65_536)
                if buffer.frameLength == 0 { break }
                if let channels = buffer.floatChannelData {
                    let bytes = Int(buffer.frameLength) * MemoryLayout<Float>.size
                    for ch in 0..<Int(format.channelCount) {
                        hasher.update(bufferPointer: UnsafeRawBufferPointer(start: channels[ch], count: bytes))
                    }
                } else if let channels = buffer.int16ChannelData {
                    let bytes = Int(buffer.frameLength) * MemoryLayout<Int16>.size
                    for ch in 0..<Int(format.channelCount) {
                        hasher.update(bufferPointer: UnsafeRawBufferPointer(start: channels[ch], count: bytes))
                    }
                }
            }
        } catch {
            lastError = "read: \(error.localizedDescription)"
            return nil
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return Result(hash: digest, duration: duration)
    }
}
