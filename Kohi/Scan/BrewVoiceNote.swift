import AVFoundation
import Foundation
import Observation
import os

/// A brew-length voice note: record to a file, transcribe afterwards.
///
/// No live recogniser. The file is what survives a locked screen; Speech only
/// runs once the brew has stopped.
@Observable
@MainActor
final class BrewVoiceNote {
    enum State: Equatable {
        case idle
        case recording
        case paused
        case transcribing
        case failed
        case denied
    }

    struct Pending: Codable, Equatable, Sendable {
        var brewID: UUID
        var startedAt: Date
        var path: String
    }

    private(set) var state: State = .idle
    private(set) var fileURL: URL?
    private(set) var startedAt: Date?
    private(set) var brewID: UUID?

    private var recorder: AVAudioRecorder?
    private var interruptionObserver: (any NSObjectProtocol)?
    private let delegate = RecorderHook()
    private var isStarting = false

    var isRecording: Bool { state == .recording }

    var hasFile: Bool {
        guard let fileURL else { return false }
        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    init() {
        delegate.owner = self
    }

    func start(brewID: UUID) async {
        guard state != .recording, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        if state == .failed || state == .denied { state = .idle }
        guard await DictationAuth.requestMicrophone() else {
            state = .denied
            return
        }
        do {
            try beginRecording(brewID: brewID)
        } catch {
            Log.app.notice("voice note could not start: \(error)")
            state = .failed
        }
    }

    private func beginRecording(brewID: UUID) throws {
        try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        let url = Self.directory.appending(path: "\(brewID.uuidString).m4a")
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        try Self.activateSession()
        let sampleRate = AVAudioSession.sharedInstance().sampleRate
        let rate = sampleRate > 0 ? sampleRate : 44_100

        let recorder = try AVAudioRecorder(
            url: url,
            settings: [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: rate,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
            ]
        )
        recorder.delegate = delegate
        recorder.prepareToRecord()
        guard recorder.record() else { throw DictationError.unavailable }

        self.recorder = recorder
        self.fileURL = url
        self.brewID = brewID
        self.startedAt = .now
        self.state = .recording
        writePending()
        watchInterruptions()
    }

    /// Drops the previous category, then walks the same plans as live dictation.
    /// A spoken-audio mode plus Bluetooth returns `-50`; that combination is
    /// not in the list.
    static func activateSession() throws {
        try DictationSession.activate(deactivateFirst: true)
    }

    nonisolated static var sessionPlans: [DictationSessionPlan] { DictationSession.plans }

    func stop() {
        recorder?.stop()
        recorder = nil
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
            self.interruptionObserver = nil
        }
        if state == .recording || state == .paused {
            state = .idle
        }
        try? AVAudioSession.sharedInstance().setActive(
            false, options: .notifyOthersOnDeactivation
        )
    }

    func transcribe(keepAudio: Bool) async throws -> String {
        stop()
        guard let fileURL, hasFile else {
            clearPending()
            state = .idle
            return ""
        }
        state = .transcribing
        do {
            let outcome = try await VoiceNoteTranscriber.transcribe(url: fileURL)
            if !keepAudio {
                try? FileManager.default.removeItem(at: fileURL)
                self.fileURL = nil
            }
            clearPending()
            state = .idle
            return outcome.text
        } catch {
            state = .failed
            throw error
        }
    }

    func attachPending(_ pending: Pending) {
        fileURL = URL(fileURLWithPath: pending.path)
        brewID = pending.brewID
        startedAt = pending.startedAt
    }

    func discard() {
        stop()
        if let fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        fileURL = nil
        brewID = nil
        startedAt = nil
        clearPending()
        state = .idle
    }

    static func pending() -> Pending? {
        guard let data = try? Data(contentsOf: pendingURL) else { return nil }
        return try? JSONDecoder().decode(Pending.self, from: data)
    }

    static func discardPending() {
        if let pending = pending() {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: pending.path))
        }
        try? FileManager.default.removeItem(at: pendingURL)
    }

    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "voice-notes", directoryHint: .isDirectory)
    }

    static var pendingURL: URL {
        directory.appending(path: "pending.json")
    }

    fileprivate func handleFinish(successfully flag: Bool) {
        if !flag { state = .failed }
        else if state == .recording { state = .idle }
    }

    fileprivate func pauseForInterruption() {
        guard state == .recording else { return }
        recorder?.pause()
        state = .paused
    }

    fileprivate func resumeAfterInterruption() {
        guard state == .paused else { return }
        do {
            try Self.activateSession()
            if recorder?.record() == true {
                state = .recording
            } else {
                state = .failed
            }
        } catch {
            Log.app.notice("voice note could not resume: \(error)")
            state = .failed
        }
    }

    private func writePending() {
        guard let brewID, let fileURL, let startedAt else { return }
        try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        let pending = Pending(brewID: brewID, startedAt: startedAt, path: fileURL.path)
        if let data = try? JSONEncoder().encode(pending) {
            try? data.write(to: Self.pendingURL, options: .atomic)
        }
    }

    private func clearPending() {
        try? FileManager.default.removeItem(at: Self.pendingURL)
    }

    private func watchInterruptions() {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { @Sendable [weak self] notification in
            let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let optionsValue = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            Task { @MainActor [weak self] in
                guard let self else { return }
                let type = typeValue.flatMap(AVAudioSession.InterruptionType.init(rawValue:))
                switch type {
                case .began:
                    self.pauseForInterruption()
                case .ended:
                    let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue ?? 0)
                    if options.contains(.shouldResume) {
                        self.resumeAfterInterruption()
                    }
                default:
                    break
                }
            }
        }
    }
}

/// AVAudioRecorder callbacks are not on the main actor.
private final class RecorderHook: NSObject, AVAudioRecorderDelegate {
    weak var owner: BrewVoiceNote?

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            owner?.handleFinish(successfully: flag)
        }
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: (any Error)?) {
        Task { @MainActor in
            owner?.handleFinish(successfully: false)
            if let error {
                Log.app.notice("voice note encode: \(error)")
            }
        }
    }
}
