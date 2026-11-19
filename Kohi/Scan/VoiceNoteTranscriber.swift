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
    /// `contextualStrings` biases recognition toward the kit and the step words.
    static func transcribe(url: URL, contextualStrings: [String] = []) async throws -> Outcome {
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
            let pass = try await recognize(url: source, contextualStrings: contextualStrings)
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
    private static func recognize(url: URL, contextualStrings: [String]) async throws -> Pass {
        var best: (pass: Pass, score: Double)?
        for locale in SpeechLocales.candidates {
            do {
                let pass = try await recognize(url: url, locale: locale, contextualStrings: contextualStrings)
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
    private static func recognize(url: URL, locale: Locale, contextualStrings: [String]) async throws -> Pass {
        guard let recognizer = SFSpeechRecognizer(locale: locale),
              recognizer.isAvailable,
              recognizer.supportsOnDeviceRecognition
        else { throw DictationError.unavailable }

        let request = SFSpeechURLRecognitionRequest(url: url)
        // Partial results are how the chunks before a pause are seen at all:
        // the final result only carries the last one.
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.requiresOnDeviceRecognition = true
        request.contextualStrings = contextualStrings

        let gate = OSAllocatedUnfairLock(initialState: false)
        let heard = OSAllocatedUnfairLock(initialState: (chunks: TranscriptChunks(), confidences: [Float]()))
        return try await withCheckedThrowingContinuation { continuation in
            recognizer.recognitionTask(with: request) { @Sendable result, error in
                if let result {
                    let segments = result.bestTranscription.segments
                    heard.withLock { state in
                        state.chunks.feed(
                            segments.map { .init(at: $0.timestamp, duration: $0.duration, text: $0.substring) },
                            endsUtterance: result.speechRecognitionMetadata != nil
                        )
                        if result.isFinal || result.speechRecognitionMetadata != nil {
                            state.confidences.append(contentsOf: segments.map(\.confidence))
                        }
                    }
                }
                let shouldSettle = error != nil || result?.isFinal == true
                guard shouldSettle else { return }
                let first = gate.withLock { fired -> Bool in
                    if fired { return false }
                    fired = true
                    return true
                }
                guard first else { return }
                let (chunks, confidences) = heard.withLock { ($0.chunks, $0.confidences) }
                // "No speech" after words were heard ends the file, it is not a failure.
                if let error, chunks.segments.isEmpty {
                    continuation.resume(throwing: error)
                    return
                }
                let text = chunks.text
                let speech = confidences.isEmpty ? 0 : Double(confidences.reduce(0, +)) / Double(confidences.count)
                continuation.resume(returning: Pass(
                    text: text,
                    coveredThrough: chunks.end,
                    phrases: chunks.segments.map { Phrase(at: $0.at, text: $0.text) },
                    score: speech + min(Double(text.count) / 400, 0.25)
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
