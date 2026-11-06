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
    /// 0…1, the recorder's level. The pill draws bars from `levels`.
    private(set) var level: Double = 0
    private(set) var levels: [Double] = []
    /// How long the kept recording is. Playback scrubs inside it.
    private(set) var recordedSeconds: TimeInterval = 0
    private(set) var progress: Double = 0
    private(set) var isPlaying = false

    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var interruptionObserver: (any NSObjectProtocol)?
    private let delegate = RecorderHook()
    private let playerDelegate = PlayerHook()
    private var isStarting = false
    private var meterTask: Task<Void, Never>?
    private var playTask: Task<Void, Never>?

    var isRecording: Bool { state == .recording }

    var hasFile: Bool {
        guard let fileURL else { return false }
        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    init() {
        delegate.owner = self
        playerDelegate.owner = self
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
        recorder.isMeteringEnabled = true
        recorder.prepareToRecord()
        guard recorder.record() else { throw DictationError.unavailable }

        self.recorder = recorder
        self.fileURL = url
        self.brewID = brewID
        self.startedAt = .now
        self.recordedSeconds = 0
        self.levels = []
        self.level = 0
        self.progress = 0
        self.state = .recording
        writePending()
        watchInterruptions()
        startMeter()
    }

    /// Drops the previous category, then walks the same plans as live dictation.
    /// A spoken-audio mode plus Bluetooth returns `-50`; that combination is
    /// not in the list.
    static func activateSession() throws {
        try DictationSession.activate(deactivateFirst: true)
    }

    nonisolated static var sessionPlans: [DictationSessionPlan] { DictationSession.plans }

    func stop() {
        if let startedAt, state == .recording || state == .paused {
            recordedSeconds = Date().timeIntervalSince(startedAt)
        }
        meterTask?.cancel()
        meterTask = nil
        stopPlayback()
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
        recordedSeconds = 0
        levels = []
        level = 0
        progress = 0
        clearPending()
        state = .idle
    }

    func togglePlayback() {
        if isPlaying {
            pausePlayback()
        } else {
            play()
        }
    }

    func play() {
        guard let fileURL, hasFile else { return }
        if player == nil {
            try? Self.activateSession()
            guard let player = try? AVAudioPlayer(contentsOf: fileURL) else { return }
            player.delegate = playerDelegate
            playerDelegate.owner = self
            player.prepareToPlay()
            self.player = player
        }
        if progress >= 0.99 {
            player?.currentTime = 0
            progress = 0
        }
        player?.play()
        isPlaying = true
        playTask?.cancel()
        playTask = Task { @MainActor in
            while !Task.isCancelled, let player, player.isPlaying {
                progress = player.duration > 0 ? player.currentTime / player.duration : 0
                try? await Task.sleep(for: .milliseconds(32))
            }
        }
    }

    func pausePlayback() {
        player?.pause()
        isPlaying = false
        playTask?.cancel()
    }

    func seek(to fraction: Double) {
        guard let player, player.duration > 0 else { return }
        let clamped = min(1, max(0, fraction))
        player.currentTime = clamped * player.duration
        progress = clamped
    }

    func stopPlayback() {
        player?.stop()
        player = nil
        isPlaying = false
        playTask?.cancel()
        progress = 0
    }

    fileprivate func handlePlaybackFinished() {
        isPlaying = false
        progress = 1
        playTask?.cancel()
    }

    private func startMeter() {
        meterTask?.cancel()
        meterTask = Task { @MainActor in
            while !Task.isCancelled {
                guard state == .recording, let recorder else { return }
                recorder.updateMeters()
                let db = recorder.averagePower(forChannel: 0)
                let linear = min(1, max(0, pow(10, Double(db) / 20)))
                level = linear
                levels.append(linear)
                if levels.count > 96 {
                    levels.removeFirst(levels.count - 96)
                }
                try? await Task.sleep(for: .milliseconds(70))
            }
        }
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
                startMeter()
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
private final class PlayerHook: NSObject, AVAudioPlayerDelegate {
    weak var owner: BrewVoiceNote?

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            owner?.handlePlaybackFinished()
        }
    }
}

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
