import AVFoundation
import Foundation
import Testing
@testable import Kohi

struct AudioGainTests {
    @Test func aQuietVoiceIsBroughtToSpeakingLevel() {
        let gain = AudioGain.gain(peak: 0.05, rms: 0.01)
        #expect(gain == AudioGain.targetRMS / 0.01)
    }

    @Test func theGainNeverClipsThePeak() {
        let gain = AudioGain.gain(peak: 0.5, rms: 0.01)
        #expect(gain * 0.5 <= AudioGain.targetPeak + 0.0001)
    }

    @Test func silenceIsNotAmplifiedIntoNoise() {
        #expect(AudioGain.gain(peak: 0.001, rms: 0.0001) == AudioGain.maxGain)
        #expect(AudioGain.gain(peak: 0, rms: 0) == 1)
    }

    @Test func aLoudFileIsLeftAlone() {
        #expect(AudioGain.gain(peak: 0.8, rms: 0.12) == 1)
    }

    @Test func aQuietRecordingComesBackLouder() async throws {
        let quiet = try Self.tone(amplitude: 0.02)
        defer { try? FileManager.default.removeItem(at: quiet) }
        let louder = await AudioGain.normalized(quiet)
        defer { if louder != quiet { try? FileManager.default.removeItem(at: louder) } }
        #expect(louder != quiet)
        #expect(try Self.peak(of: louder) > 0.12)
    }

    @Test func aLoudRecordingIsNotCopied() async throws {
        let loud = try Self.tone(amplitude: 0.8)
        defer { try? FileManager.default.removeItem(at: loud) }
        #expect(await AudioGain.normalized(loud) == loud)
    }

    private static func tone(amplitude: Float) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "tone-\(UUID().uuidString).m4a")
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let file = try AVAudioFile(
            forWriting: url,
            settings: [AVFormatIDKey: Int(kAudioFormatMPEG4AAC), AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1],
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        let frames: AVAudioFrameCount = 44_100
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for index in 0..<Int(frames) {
            buffer.floatChannelData![0][index] = amplitude * sin(2 * .pi * 220 * Float(index) / 44_100)
        }
        try file.write(from: buffer)
        return url
    }

    private static func peak(of url: URL) throws -> Float {
        let file = try AVAudioFile(forReading: url)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)
        var peak: Float = 0
        for index in 0..<Int(buffer.frameLength) { peak = max(peak, abs(buffer.floatChannelData![0][index])) }
        return peak
    }
}
