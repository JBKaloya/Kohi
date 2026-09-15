import AVFoundation
import Foundation
import Speech
import os

/// The iOS 26 transcriber, wrapped so `Dictation` holds one thing whichever
/// engine is running.
///
/// `SpeechAnalyzer` consumes an async sequence of buffers rather than taking a
/// tap callback, so the audio tap feeds a continuation and the analyzer reads
/// from the other end.
///
/// Isolated to the main actor so `SpeechAnalyzer.start` is not called from
/// the Swift concurrent pool — that is a libdispatch assertion (the dictation
/// crash: "Block was expected to execute on queue").
@available(iOS 26.0, *)
@MainActor
final class SpeechAnalyzerSession: AnalyzerSession {
    private let analyzer: SpeechAnalyzer
    private let transcriber: SpeechTranscriber
    private let stream: AsyncStream<AnalyzerInput>
    private let feed: AsyncStream<AnalyzerInput>.Continuation
    private let format: AVAudioFormat
    private let work: [Task<Void, Never>]

    /// Throws when the locale has no model installed and none can be
    /// installed, which is the one case where the caller must fall back.
    init(locale: Locale, onTranscript: @escaping @Sendable (String) -> Void) async throws {
        guard SpeechTranscriber.isAvailable else { throw DictationError.unavailable }

        let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale)
            ?? Locale(identifier: "en-US")

        transcriber = SpeechTranscriber(
            locale: supported,
            // Volatile results are what make the text appear as you speak;
            // without them the field stays empty until you stop, which reads
            // as a hang.
            preset: .progressiveTranscription
        )

        if await AssetInventory.status(forModules: [transcriber]) != .installed,
           let request = try await AssetInventory.assetInstallationRequest(
               supporting: [transcriber]
           ) {
            try await request.downloadAndInstall()
        }

        analyzer = SpeechAnalyzer(modules: [transcriber])

        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [transcriber]
        ) else { throw DictationError.unavailable }
        self.format = format

        (stream, feed) = AsyncStream<AnalyzerInput>.makeStream()

        // Volatile results are replacements for the tail, finalised ones are
        // settled prefix. Keeping them apart is what stops the text flickering
        // between two readings of the same words.
        let results = Task { @MainActor [transcriber] in
            var settled = ""
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    if result.isFinal {
                        settled += text
                        onTranscript(settled)
                    } else {
                        onTranscript(settled + text)
                    }
                }
            } catch {
                Log.app.notice("transcriber ended: \(error)")
            }
        }

        // Must stay on the main queue. SpeechAnalyzer.start asserts a
        // dispatch queue; a Swift concurrent-pool Task is the other crash.
        let analysis = Task { @MainActor [analyzer, stream] in
            do {
                try await analyzer.start(inputSequence: stream)
            } catch {
                Log.app.notice("analyzer ended: \(error)")
            }
        }
        work = [results, analysis]
    }

    func attach(to engine: AVAudioEngine) throws {
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw DictationError.unavailable
        }
        guard let converter = AVAudioConverter(from: inputFormat, to: format) else {
            throw DictationError.unavailable
        }

        // Caller owns tap lifetime. removeTap here would crash on first use.
        let format = format
        let feed = feed
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
            guard let converted = Self.convert(buffer, with: converter, to: format) else {
                return
            }
            feed.yield(AnalyzerInput(buffer: converted))
        }
    }

    func finish() async {
        feed.finish()
        try? await analyzer.finalizeAndFinishThroughEndOfInput()

        // Finalising delivers the last results, but the loop reading them can
        // still be a hop behind: let it end with the stream, and cut it short
        // only if it does not, so a stuck module cannot hold the sheet open.
        let pending = work
        let deadline = Task {
            try? await Task.sleep(for: .milliseconds(300))
            pending.forEach { $0.cancel() }
        }
        for task in pending { await task.value }
        deadline.cancel()
    }

    /// The microphone's format is rarely the one the model wants.
    private static func convert(
        _ buffer: AVAudioPCMBuffer,
        with converter: AVAudioConverter,
        to format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 1024)
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            return nil
        }

        var consumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        return error == nil && output.frameLength > 0 ? output : nil
    }
}
