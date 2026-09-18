import AVFoundation
import Foundation
import Speech
import os

/// The iOS 26 transcriber, wrapped so `Dictation` holds one thing whichever
/// engine is running.
///
/// Parked. `Dictation` no longer starts this — on device, `SpeechAnalyzer`
/// hits `_dispatch_assert_queue_fail` (`EXC_BREAKPOINT`) even when the
/// session is `@MainActor`. Keep the type so the iOS 26 path can come back
/// once Speech is safe to call from Swift concurrency.
@available(iOS 26.0, *)
@MainActor
final class SpeechAnalyzerSession {
    private let analyzer: SpeechAnalyzer
    private let transcriber: SpeechTranscriber
    private let stream: AsyncStream<AnalyzerInput>
    private let feed: AsyncStream<AnalyzerInput>.Continuation
    private let format: AVAudioFormat
    private let results: Task<Void, Never>

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

        (stream, feed) = AsyncStream<AnalyzerInput>.makeStream(
            bufferingPolicy: .bufferingNewest(12)
        )

        // Volatile results are replacements for the tail, finalised ones are
        // settled prefix. Keeping them apart is what stops the text flickering
        // between two readings of the same words.
        let transcriber = transcriber
        results = Task { [transcriber] in
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
    }

    /// Arms the analyzer. Returns once it is ready to consume buffers — the
    /// microphone tap is installed afterwards, never before.
    func startListening() async throws {
        try await analyzer.start(inputSequence: stream)
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
        results.cancel()
        await results.value
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
