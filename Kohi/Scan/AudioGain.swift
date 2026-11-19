import AVFoundation
import Foundation
import os

/// Brings a quiet brew note up to speaking level before Speech, the model or
/// the archive hear it. A note recorded a metre from the phone, kettle
/// running, peaks far below full scale; recognition degrades with it.
nonisolated enum AudioGain {
    /// Loudest sample after the gain, in full scale. Headroom for AAC.
    static let targetPeak: Float = 0.89
    /// The level speech should sit at, RMS in full scale (about -20 dBFS).
    static let targetRMS: Float = 0.1
    /// Never more than this (+24 dB): beyond it the noise floor is all that grows.
    static let maxGain: Float = 16
    /// Below this the file is left as it is.
    static let minGain: Float = 1.12

    /// The gain for a file with this peak and RMS: enough to bring speech to
    /// `targetRMS`, never so much that the peak clips, never past `maxGain`.
    static func gain(peak: Float, rms: Float) -> Float {
        guard peak > 0, rms > 0 else { return 1 }
        let gain = min(targetRMS / rms, targetPeak / peak, maxGain)
        return gain < minGain ? 1 : gain
    }

    /// A louder copy in the temporary directory, or `url` itself when it is
    /// already loud enough or cannot be read.
    @concurrent
    static func normalized(_ url: URL) async -> URL {
        do {
            let file = try AVAudioFile(forReading: url)
            let format = file.processingFormat
            let frames = AVAudioFrameCount(file.length)
            guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return url }
            try file.read(into: buffer)
            guard let channels = buffer.floatChannelData else { return url }

            var peak: Float = 0
            var squares: Double = 0
            let count = Int(buffer.frameLength)
            let channelCount = Int(format.channelCount)
            for channel in 0..<channelCount {
                let samples = channels[channel]
                for index in 0..<count {
                    let value = samples[index]
                    peak = max(peak, abs(value))
                    squares += Double(value * value)
                }
            }
            let rms = Float((squares / Double(max(count * channelCount, 1))).squareRoot())
            let gain = gain(peak: peak, rms: rms)
            guard gain > 1 else { return url }

            for channel in 0..<channelCount {
                let samples = channels[channel]
                for index in 0..<count {
                    samples[index] = max(-1, min(1, samples[index] * gain))
                }
            }

            let output = FileManager.default.temporaryDirectory
                .appending(path: "kohi-louder-\(UUID().uuidString).m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: format.sampleRate,
                AVNumberOfChannelsKey: format.channelCount,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ]
            do {
                let louder = try AVAudioFile(
                    forWriting: output,
                    settings: settings,
                    commonFormat: .pcmFormatFloat32,
                    interleaved: false
                )
                try louder.write(from: buffer)
            }
            return output
        } catch {
            Log.app.notice("audio gain skipped: \(error)")
            return url
        }
    }
}
