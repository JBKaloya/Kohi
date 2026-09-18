import AVFoundation
import Foundation
import Observation
import Speech
import os

/// Speech to text, on device, for the length of a sentence.
///
/// `SFSpeechRecognizer` only. Two live crashes that look like Speech:
/// 1. `requestPermission()`: Speech and AVAudio call back off the main actor,
///    and resuming a main-actor continuation from that callback is a Swift 6
///    isolation trap (`_swift_task_checkIsolatedSwift` → libdispatch).
/// 2. `AVAudioEngine.prepare()` before `inputNode` exists. CoreAudio aborts
///    with `inputNode != nil || outputNode != nil` — an `NSException`, not a
///    Swift Error, so `do/catch` cannot save it. Touch `inputNode` first;
///    `start()` prepares the graph itself.
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

    /// Fresh each listen. Reusing a stopped engine and calling `prepare()` on
    /// an empty graph is the CoreAudio abort above.
    private var engine: AVAudioEngine?
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
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
        guard DictationMic.acquire() else { return }
        isStarting = true
        defer { isStarting = false }
        transcript = ""

        guard await DictationAuth.request() else {
            DictationMic.release()
            state = .denied
            return
        }

        do {
            try configureSession()
            try await startRecognizer()
            state = .listening
        } catch {
            Log.app.error("dictation could not start: \(error)")
            tearDown()
            state = .unavailable
        }
    }

    /// Ends the recording and returns the final transcript. Returning it
    /// rather than only publishing it means the caller cannot act on a stale
    /// value by mistake.
    @discardableResult
    func stop() async -> String {
        tearDown()
        return transcript
    }

    /// Ends the recording without waiting for a last result, for when the
    /// screen is going away and nobody is left to read the text.
    func cancel() {
        tearDown()
    }

    // MARK: - Audio graph

    private func tearDown() {
        if let engine {
            if engine.isRunning { engine.stop() }
            if hasTap {
                engine.inputNode.removeTap(onBus: 0)
                hasTap = false
            }
            engine.reset()
        }
        engine = nil
        request?.endAudio()
        request = nil
        task = nil
        recognizer = nil
        try? AVAudioSession.sharedInstance().setActive(
            false, options: .notifyOthersOnDeactivation
        )
        if state == .listening { state = .idle }
        DictationMic.release()
    }

    private func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func startRecognizer() async throws {
        let recognizer = SFSpeechRecognizer(locale: .current)
            ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        guard let recognizer, recognizer.isAvailable else {
            throw DictationError.unavailable
        }
        recognizer.defaultTaskHint = .dictation
        self.recognizer = recognizer

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        } else {
            Log.app.notice("on-device recognition unavailable for \(Locale.current.identifier)")
            throw DictationError.unavailable
        }
        self.request = request

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal == true
            let err = error
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let text { self.transcript = text }
                if let err {
                    Log.app.notice("dictation: \(err)")
                    self.tearDown()
                    self.state = .unavailable
                    return
                }
                if isFinal, self.state == .listening {
                    self.tearDown()
                }
            }
        }

        let engine = AVAudioEngine()
        self.engine = engine
        // Accessing `inputNode` is what creates it. `prepare()` before that
        // aborts in CoreAudio and is not a Swift error.
        let input = engine.inputNode
        let format = try await hardwareFormat(on: input)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        hasTap = true
        try engine.start()
    }

    /// After the first mic grant the node can still report 0 Hz for a beat.
    /// Wait; do not `prepare()` an empty graph to force a format.
    private func hardwareFormat(on input: AVAudioInputNode) async throws -> AVAudioFormat {
        for attempt in 0..<8 {
            let format = input.outputFormat(forBus: 0)
            if format.sampleRate > 0, format.channelCount > 0 {
                return format
            }
            if attempt == 0 {
                try AVAudioSession.sharedInstance().setActive(true)
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw DictationError.unavailable
    }
}

/// Speech / mic permission callbacks are not on the main actor.
///
/// Approachable concurrency (`NonisolatedNonsendingByDefault`) keeps a
/// `nonisolated async` function on the caller's actor. `start()` is on
/// the main actor, so a continuation created there is main-actor isolated —
/// and Speech resumes it on `com.apple.root.default-qos`, which is the
/// libdispatch breakpoint. `@concurrent` hops off before the wait.
nonisolated enum DictationAuth {
    @concurrent
    static func request() async -> Bool {
        let speech: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard speech == .authorized else { return false }

        return await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { allowed in
                continuation.resume(returning: allowed)
            }
        }
    }
}

/// One microphone. Brew has a page-level Dictate and a notes field; both
/// would otherwise install a tap on the same input node.
@MainActor
private enum DictationMic {
    static var busy = false

    static func acquire() -> Bool {
        if busy { return false }
        busy = true
        return true
    }

    static func release() {
        busy = false
    }
}

enum DictationError: Error {
    case unavailable
}
