import AVFoundation
import Foundation
import Observation
import Speech
import os

/// Speech to text, on device, for the length of a sentence.
///
/// Two engines behind one surface: `SpeechAnalyzer` on iOS 26, which is
/// faster and needs no server, and `SFSpeechRecognizer` before that. Both are
/// forced on device — a brew note is not worth sending to Apple either.
@Observable
@MainActor
final class Dictation {
    enum State: Equatable {
        case idle
        case listening
        case denied
        case unavailable
    }

    private(set) var state: State = .idle
    /// What has been heard so far, updated as you speak.
    private(set) var transcript = ""

    private let engine = AVAudioEngine()

    // The pre-26 path.
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    // The iOS 26 path, kept opaque so the type does not leak into the build
    // on older SDK paths.
    private var analyzerSession: (any AnalyzerSession)?
    /// `removeTap` throws if nothing is installed. The engine does not tell
    /// us, so we have to.
    private var hasTap = false
    private var isStarting = false

    var isListening: Bool { state == .listening }

    /// Whether dictation can work at all here. Checked before the button is
    /// drawn, so nothing offers what it cannot do.
    static var isSupported: Bool {
        if SFSpeechRecognizer(locale: .current)?.isAvailable == true { return true }
        return SFSpeechRecognizer(locale: Locale(identifier: "en-US"))?.isAvailable ?? false
    }

    // MARK: - Lifecycle

    func start() async {
        guard state != .listening, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        transcript = ""

        guard await requestPermission() else {
            state = .denied
            return
        }

        do {
            try configureSession()
            if #available(iOS 26.0, *) {
                try await startAnalyzer()
            } else {
                try startRecognizer()
            }
            state = .listening
        } catch {
            Log.app.error("dictation could not start: \(error)")
            cancel()
            state = .unavailable
        }
    }

    /// Ends the recording and returns the final transcript. Returning it
    /// rather than only publishing it means the caller cannot act on a stale
    /// value by mistake — which is also why this waits for the engine to hand
    /// over its last words instead of reading whatever had arrived so far.
    @discardableResult
    func stop() async -> String {
        let session = releaseAudio()
        await session?.finish()
        endSession()
        return transcript
    }

    /// Ends the recording without waiting for a last result, for when the
    /// screen is going away and nobody is left to read the text.
    func cancel() {
        let session = releaseAudio()
        if let session { Task { await session.finish() } }
        endSession()
    }

    /// Stops the microphone and hands back the analyzer session still owing a
    /// final result, if there is one.
    private func releaseAudio() -> (any AnalyzerSession)? {
        stopCapture(finishTask: true)
        defer { analyzerSession = nil }
        return analyzerSession
    }

    /// Tear down the tap without finishing the recognition task — the
    /// callback already owns that, and `finish()` from inside it is the
    /// libdispatch assertion.
    private func finishListening() {
        stopCapture(finishTask: false)
        endSession()
    }

    private func failListening() {
        stopCapture(finishTask: false)
        endSession()
        state = .unavailable
    }

    private func stopCapture(finishTask: Bool) {
        if engine.isRunning { engine.stop() }
        removeTapIfNeeded()
        engine.reset()
        request?.endAudio()
        if finishTask { task?.finish() }
        request = nil
        task = nil
        recognizer = nil
    }

    private func removeTapIfNeeded() {
        guard hasTap else { return }
        engine.inputNode.removeTap(onBus: 0)
        hasTap = false
    }

    private func endSession() {
        try? AVAudioSession.sharedInstance().setActive(
            false, options: .notifyOthersOnDeactivation
        )
        if state == .listening { state = .idle }
    }

    private func requestPermission() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speech == .authorized else { return false }

        return await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
    }

    private func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    // MARK: - SFSpeechRecognizer, iOS 18 to 25

    private func startRecognizer() throws {
        let recognizer = SFSpeechRecognizer(locale: .current)
            ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        guard let recognizer, recognizer.isAvailable else {
            throw DictationError.unavailable
        }
        self.recognizer = recognizer

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        // On-device FR is often missing; requiring it crashes the recogniser
        // instead of failing cleanly. We only force it when the locale can.
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        } else {
            Log.app.notice("on-device recognition unavailable for \(Locale.current.identifier)")
            throw DictationError.unavailable
        }
        self.request = request

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }
                if let error {
                    Log.app.notice("dictation: \(error)")
                    self.failListening()
                    return
                }
                if result?.isFinal == true {
                    self.finishListening()
                }
            }
        }

        let format = try preparedInputFormat()
        removeTapIfNeeded()
        engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        hasTap = true
        engine.prepare()
        try engine.start()
    }

    /// After the first mic grant the input node can still report 0 Hz until
    /// the session is active and the graph is prepared.
    private func preparedInputFormat() throws -> AVAudioFormat {
        engine.prepare()
        var format = engine.inputNode.outputFormat(forBus: 0)
        if format.sampleRate <= 0 || format.channelCount <= 0 {
            try AVAudioSession.sharedInstance().setActive(true)
            engine.prepare()
            format = engine.inputNode.outputFormat(forBus: 0)
        }
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw DictationError.unavailable
        }
        return format
    }

    // MARK: - SpeechAnalyzer, iOS 26

    @available(iOS 26.0, *)
    private func startAnalyzer() async throws {
        do {
            let session = try await SpeechAnalyzerSession(locale: .current) { [weak self] text in
                Task { @MainActor in self?.transcript = text }
            }
            analyzerSession = session
            _ = try preparedInputFormat()
            removeTapIfNeeded()
            try session.attach(to: engine)
            hasTap = true
            engine.prepare()
            try engine.start()
        } catch {
            // No model for this locale, or the analyzer refused: the older
            // recogniser is still there. Never removeTap here unless we
            // installed one — that exception is the Dictate crash.
            Log.app.notice("speech analyzer unavailable, using the recogniser (\(error))")
            if let session = analyzerSession {
                analyzerSession = nil
                Task { await session.finish() }
            }
            try startRecognizer()
        }
    }
}

enum DictationError: Error {
    case unavailable
}

/// The shape both engines are used through, so `Dictation` holds one thing.
protocol AnalyzerSession: AnyObject {
    func attach(to engine: AVAudioEngine) throws
    /// Ends the feed and returns once the last result has been delivered.
    func finish() async
}
