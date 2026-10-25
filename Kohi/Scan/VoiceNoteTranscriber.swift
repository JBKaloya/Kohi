import AVFoundation
import Foundation
import Speech
import os

/// On-device transcription of a recorded brew note.
nonisolated enum VoiceNoteTranscriber {
    struct Phrase: Equatable, Sendable {
        var at: TimeInterval
        var text: String
    }

    struct Outcome: Equatable, Sendable {
        var text: String
        var coveredThrough: TimeInterval
        var duration: TimeInterval
        var phrases: [Phrase]
    }

    @concurrent
    static func transcribe(url: URL) async throws -> Outcome {
        let duration = try await assetDuration(url)
        var collected = ""
        var covered: TimeInterval = 0
        var origin: TimeInterval = 0
        var phrases: [Phrase] = []
        var source = url
        var temps: [URL] = []
        defer {
            for temp in temps { try? FileManager.default.removeItem(at: temp) }
        }

        for _ in 0..<VoiceNoteCoverage.maxPasses {
            let pass = try await recognize(url: source)
            collected = DictationTranscript.join(collected, pass.text)
            covered = VoiceNoteCoverage.coveredThrough(
                origin: origin,
                relativeEnd: pass.coveredThrough
            )
            phrases.append(contentsOf: pass.phrases.map {
                Phrase(at: origin + $0.at, text: $0.text)
            })
            guard let rest = VoiceNoteCoverage.uncoveredRange(
                coveredThrough: covered,
                duration: duration
            ) else {
                break
            }
            let trimmed = try await export(url: url, range: rest)
            temps.append(trimmed)
            source = trimmed
            origin = rest.lowerBound
        }

        return Outcome(text: collected, coveredThrough: covered, duration: duration, phrases: phrases)
    }

    private struct Pass: Sendable {
        var text: String
        var coveredThrough: TimeInterval
        var phrases: [Phrase]
        var score: Double
    }

    @concurrent
    private static func recognize(url: URL) async throws -> Pass {
        var best: (pass: Pass, score: Double)?
        for locale in SpeechLocales.candidates {
            do {
                let pass = try await recognize(url: url, locale: locale)
                if best == nil || pass.score > best!.score {
                    best = (pass, pass.score)
                }
            } catch {
                continue
            }
        }
        guard let best else { throw DictationError.unavailable }
        return best.pass
    }

    /// `@concurrent` so the continuation is never main-actor isolated, even
    /// if a later caller is. Speech resumes the handler on a background queue.
    @concurrent
    private static func recognize(url: URL, locale: Locale) async throws -> Pass {
        guard let recognizer = SFSpeechRecognizer(locale: locale),
              recognizer.isAvailable,
              recognizer.supportsOnDeviceRecognition
        else { throw DictationError.unavailable }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        request.requiresOnDeviceRecognition = true

        let gate = OSAllocatedUnfairLock(initialState: false)
        return try await withCheckedThrowingContinuation { continuation in
            recognizer.recognitionTask(with: request) { @Sendable result, error in
                let shouldSettle = error != nil || result?.isFinal == true
                guard shouldSettle else { return }
                let first = gate.withLock { fired -> Bool in
                    if fired { return false }
                    fired = true
                    return true
                }
                guard first else { return }
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let result else { return }
                let text = result.bestTranscription.formattedString
                let last = result.bestTranscription.segments.last
                let end = last.map { $0.timestamp + $0.duration } ?? 0
                let phrases = result.bestTranscription.segments.map {
                    Phrase(at: $0.timestamp, text: $0.substring)
                }
                let score = SpeechLocales.score(text: text, segments: result.bestTranscription.segments)
                continuation.resume(returning: Pass(
                    text: text,
                    coveredThrough: end,
                    phrases: phrases,
                    score: score
                ))
            }
        }
    }

    private static func assetDuration(_ url: URL) async throws -> TimeInterval {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        return CMTimeGetSeconds(duration)
    }

    private static func export(
        url: URL,
        range: ClosedRange<TimeInterval>
    ) async throws -> URL {
        let asset = AVURLAsset(url: url)
        let start = CMTime(seconds: range.lowerBound, preferredTimescale: 600)
        let end = CMTime(seconds: range.upperBound, preferredTimescale: 600)
        guard let session = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw DictationError.unavailable
        }
        let output = FileManager.default.temporaryDirectory
            .appending(path: "kohi-voice-\(UUID().uuidString).m4a")
        session.timeRange = CMTimeRangeFromTimeToTime(start: start, end: end)
        if FileManager.default.fileExists(atPath: output.path) {
            try FileManager.default.removeItem(at: output)
        }
        if #available(iOS 18.0, *) {
            try await session.export(to: output, as: .m4a)
        } else {
            session.outputURL = output
            session.outputFileType = .m4a
            await session.export()
            if session.status != .completed {
                throw session.error ?? DictationError.unavailable
            }
        }
        return output
    }
}
