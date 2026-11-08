import AVFoundation
import Foundation
import Observation
import Speech
import UIKit
import os

/// On-device locales Kohi actually speaks: the phone, plus English and French.
/// A French phone with English narration was decoding "put some water" as
/// "Official player, do you taught?" because only `Locale.current` ran.
nonisolated enum SpeechLocales {
    static var candidates: [Locale] {
        var seen = Set<String>()
        var list: [Locale] = []
        for locale in [Locale.current, Locale(identifier: "en-US"), Locale(identifier: "fr-FR")] {
            let key = locale.language.languageCode?.identifier ?? locale.identifier
            if seen.insert(key).inserted { list.append(locale) }
        }
        return list
    }

    static func recognizers() -> [SFSpeechRecognizer] {
        candidates.compactMap { locale in
            guard let recognizer = SFSpeechRecognizer(locale: locale),
                  recognizer.isAvailable,
                  recognizer.supportsOnDeviceRecognition
            else { return nil }
            return recognizer
        }
    }

    static func score(text: String, segments: [SFTranscriptionSegment] = []) -> Double {
        let speech: Double
        if segments.isEmpty {
            speech = 0
        } else {
            speech = Double(segments.map(\.confidence).reduce(0, +)) / Double(segments.count)
        }
        return speech + min(Double(text.count) / 400, 0.25)
    }
}

/// Speech to text, on device, for as long as the user keeps the mic open.
///
/// `SFSpeechRecognizer` only. Two live crashes that look like Speech:
/// 1. `requestPermission()`: Speech and AVAudio call back off the main actor,
///    and resuming a main-actor continuation from that callback is a Swift 6
///    isolation trap (`_swift_task_checkIsolatedSwift` → libdispatch).
/// 2. `AVAudioEngine.prepare()` before `inputNode` exists. CoreAudio aborts
///    with `inputNode != nil || outputNode != nil` — an `NSException`, not a
///    Swift Error, so `do/catch` cannot save it. Touch `inputNode` first;
///    `start()` prepares the graph itself.
///
/// A pause in speech finalises the current request. The engine stays up and a
/// new request takes over, so a brew narration can stop to pour and keep going.
@Observable
@MainActor
final class Dictation {
    enum State: Equatable {
        case idle
        case listening
        case paused
        case busy
        case denied
        case unavailable
    }

    private(set) var state: State = .idle
    /// Settled words plus the live tail, updated as you speak.
    private(set) var transcript = ""
    /// Phrases to bias recognition toward, set before `start()`. Each new
    /// request picks them up, rolling restarts included.
    var contextualStrings: [String] = []

    /// Fresh each listen. Reusing a stopped engine and calling `prepare()` on
    /// an empty graph is the CoreAudio abort above.
    private var engine: AVAudioEngine?
    private var recognizers: [SFSpeechRecognizer] = []
    private var requests: [String: SFSpeechAudioBufferRecognitionRequest] = [:]
    private var tasks: [String: SFSpeechRecognitionTask] = [:]
    private var liveByLocale: [String: String] = [:]
    private var settledByLocale: [String: String] = [:]
    private var confidenceByLocale: [String: Float] = [:]
    /// `removeTap` throws if nothing is installed. The engine does not tell
    /// us, so we have to.
    private var hasTap = false
    private var isStarting = false
    /// The tap callback is not on the main actor. Flip this before `endAudio`
    /// so a late buffer cannot append after teardown.
    private let bufferGate = OSAllocatedUnfairLock(initialState: false)
    /// The tap must always see the current request across rolling restarts.
    /// `SFSpeechAudioBufferRecognitionRequest` is not Sendable, so the box is
    /// an unchecked holder rather than an unfair lock.
    private let requestBox = RequestHolder()
    /// Bumped when the live requests are retired. A callback still in flight
    /// from the previous request carries the old value and is ignored.
    private var requestGeneration = 0
    /// Speech and audio-session callbacks are not on the main actor. This box
    /// is what they capture, instead of `self`.
    private let events = DictationEvents()
    private var routeObserver: (any NSObjectProtocol)?
    private var interruptionObserver: (any NSObjectProtocol)?
    private var settled = ""
    private var live = ""
    private var consecutiveFailures = 0

    var isListening: Bool { state == .listening }

    /// Whether a recogniser is ready right now. Never used to hide the mic —
    /// a tap explains what is missing and may install the locale.
    static var isSupported: Bool {
        !SpeechLocales.recognizers().isEmpty
            || usable(SFSpeechRecognizer(locale: .current))
            || usable(SFSpeechRecognizer(locale: Locale(identifier: "en-US")))
            || usable(SFSpeechRecognizer(locale: Locale(identifier: "fr-FR")))
    }

    private static func usable(_ recognizer: SFSpeechRecognizer?) -> Bool {
        guard let recognizer, recognizer.isAvailable else { return false }
        return recognizer.supportsOnDeviceRecognition
    }

    nonisolated deinit {
        DictationMic.release(id: ObjectIdentifier(self))
    }

    // MARK: - Lifecycle

    func reset() {
        settled = ""
        live = ""
        transcript = ""
        consecutiveFailures = 0
        liveByLocale = [:]
        settledByLocale = [:]
        confidenceByLocale = [:]
    }

    func start() async {
        events.owner = self
        guard state != .listening, state != .paused, !isStarting else { return }
        if state == .unavailable || state == .busy || state == .denied {
            state = .idle
        }

        guard DictationMic.acquire(self) else {
            state = .busy
            return
        }
        isStarting = true
        defer { isStarting = false }

        guard await DictationAuth.request() else {
            DictationMic.release(self)
            state = .denied
            return
        }

        if !Self.isSupported {
            if #available(iOS 26.0, *), await Self.installOnDeviceLocales() {
                // Locale models landed; the recogniser should accept on-device now.
            } else {
                DictationMic.release(self)
                state = .unavailable
                return
            }
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
        settleLive()
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
        let retired = disarmRequests()
        if let routeObserver {
            NotificationCenter.default.removeObserver(routeObserver)
            self.routeObserver = nil
        }
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
            self.interruptionObserver = nil
        }
        if let engine {
            if engine.isRunning { engine.stop() }
            if hasTap {
                engine.inputNode.removeTap(onBus: 0)
                hasTap = false
            }
            engine.reset()
        }
        engine = nil
        finish(retired)
        recognizers = []
        liveByLocale = [:]
        settledByLocale = [:]
        confidenceByLocale = [:]
        consecutiveFailures = 0
        try? AVAudioSession.sharedInstance().setActive(
            false, options: .notifyOthersOnDeactivation
        )
        if state == .listening || state == .paused || state == .busy { state = .idle }
        DictationMic.release(self)
    }

    /// Closes the tap, then drops the requests the tap can see. `endAudio`
    /// happens afterwards, in `finish`, so a buffer cannot append to a
    /// request that has already ended.
    private func disarmRequests() -> [SFSpeechAudioBufferRecognitionRequest] {
        bufferGate.withLock { $0 = false }
        requestGeneration += 1
        return requestBox.replace(with: [])
    }

    private func finish(_ retired: [SFSpeechAudioBufferRecognitionRequest]) {
        for request in retired { request.endAudio() }
        for task in tasks.values { task.cancel() }
        requests = [:]
        tasks = [:]
    }

    private func configureSession() throws {
        // Leave the session active. Deactivating here cuts a graph that is
        // already coming up. Brew notes deactivate first; they are not.
        try DictationSession.activate(deactivateFirst: false)
    }

    private func startRecognizer() async throws {
        let usable = SpeechLocales.recognizers()
        guard !usable.isEmpty else { throw DictationError.unavailable }
        recognizers = usable

        let engine = AVAudioEngine()
        self.engine = engine
        // Accessing `inputNode` is what creates it. `prepare()` before that
        // aborts in CoreAudio and is not a Swift error.
        let input = engine.inputNode
        let format = try await hardwareFormat(on: input)
        bufferGate.withLock { $0 = true }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [bufferGate, requestBox] buffer, _ in
            guard bufferGate.withLock({ $0 }) else { return }
            requestBox.append(buffer)
        }
        hasTap = true
        try engine.start()
        attachRequests()
        watchRouteChanges()
        watchInterruptions()
    }

    private func attachRequests() {
        let generation = requestGeneration
        let events = events
        var attached: [SFSpeechAudioBufferRecognitionRequest] = []
        for recognizer in recognizers {
            let localeID = recognizer.locale.identifier
            recognizer.defaultTaskHint = .dictation
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.addsPunctuation = true
            request.contextualStrings = contextualStrings
            if recognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
            }
            requests[localeID] = request
            attached.append(request)
            // Speech calls this block off the main actor. `@Sendable` keeps it
            // off the main actor too; `events` hops back once the values are
            // plain data.
            tasks[localeID] = recognizer.recognitionTask(with: request) { @Sendable result, error in
                let text = result?.bestTranscription.formattedString
                let isFinal = result?.isFinal == true
                let nsError = error as NSError?
                let segments = result?.bestTranscription.segments ?? []
                let confidence = segments.map(\.confidence).max() ?? 0
                events.recognition(
                    localeID: localeID,
                    text: text,
                    isFinal: isFinal,
                    error: nsError,
                    confidence: confidence,
                    generation: generation
                )
            }
        }
        requestBox.replace(with: attached)
    }

    private func handleRecognition(
        localeID: String,
        text: String?,
        isFinal: Bool,
        error: Error?,
        confidence: Float
    ) {
        if let text {
            liveByLocale[localeID] = text
            confidenceByLocale[localeID] = confidence
            publish()
            if !text.isEmpty { consecutiveFailures = 0 }
        }
        if let error {
            Log.app.notice("dictation: \(error)")
            if recognizers.count > 1 { return }
            switch DictationFailure.classify(error) {
            case .retry:
                if state == .listening { rollRecognition() }
            case .giveUp:
                consecutiveFailures += 1
                if consecutiveFailures >= 3 {
                    tearDown()
                    state = .unavailable
                } else if state == .listening {
                    rollRecognition()
                }
            }
            return
        }
        if isFinal, state == .listening {
            settleLive()
            rollRecognition()
        }
    }

    private func rollRecognition() {
        let retired = disarmRequests()
        finish(retired)
        guard !recognizers.isEmpty, state == .listening else { return }
        attachRequests()
        bufferGate.withLock { $0 = true }
    }

    private func settleLive() {
        for (localeID, piece) in liveByLocale {
            settledByLocale[localeID] = DictationTranscript.join(
                settledByLocale[localeID] ?? "",
                piece
            )
        }
        liveByLocale = [:]
        publish()
    }

    private func publish() {
        let locales = Set(settledByLocale.keys).union(liveByLocale.keys)
        var bestText = ""
        var bestScore = -1.0
        for localeID in locales {
            let text = DictationTranscript.join(
                settledByLocale[localeID] ?? "",
                liveByLocale[localeID] ?? ""
            )
            let score = SpeechLocales.score(
                text: text,
                segments: []
            ) + Double(confidenceByLocale[localeID] ?? 0)
            if score > bestScore {
                bestScore = score
                bestText = text
            }
        }
        transcript = bestText
        settled = bestText
        live = ""
    }

    private func rebuildTap() {
        guard let engine else { return }
        do {
            if hasTap {
                engine.inputNode.removeTap(onBus: 0)
                hasTap = false
            }
            let format = engine.inputNode.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw DictationError.unavailable
            }
            bufferGate.withLock { $0 = true }
            engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [bufferGate, requestBox] buffer, _ in
                guard bufferGate.withLock({ $0 }) else { return }
                requestBox.append(buffer)
            }
            hasTap = true
            if !engine.isRunning { try engine.start() }
            if state == .listening { rollRecognition() }
        } catch {
            Log.app.notice("dictation route rebuild failed: \(error)")
            tearDown()
            state = .unavailable
        }
    }

    private func watchRouteChanges() {
        if let routeObserver {
            NotificationCenter.default.removeObserver(routeObserver)
        }
        let events = events
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { @Sendable notification in
            let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            events.routeChanged(reasonValue)
        }
    }

    fileprivate func receiveRouteChange(_ reasonValue: UInt?) {
        guard state == .listening || state == .paused else { return }
        let reason = reasonValue.flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
        guard let reason, DictationRouteChange.shouldRebuild(reason) else { return }
        rebuildTap()
    }

    private func watchInterruptions() {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        let events = events
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { @Sendable notification in
            let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let optionsValue = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            events.interrupted(typeValue: typeValue, optionsValue: optionsValue)
        }
    }

    fileprivate func receiveInterruption(typeValue: UInt?, optionsValue: UInt?) {
        let type = typeValue.flatMap(AVAudioSession.InterruptionType.init(rawValue:))
        switch type {
        case .began:
            pauseForInterruption()
        case .ended:
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue ?? 0)
            if options.contains(.shouldResume) {
                resumeAfterInterruption()
            }
        default:
            break
        }
    }

    fileprivate func receiveRecognition(
        localeID: String,
        text: String?,
        isFinal: Bool,
        error: NSError?,
        confidence: Float,
        generation: Int
    ) {
        guard requestGeneration == generation else { return }
        handleRecognition(
            localeID: localeID,
            text: text,
            isFinal: isFinal,
            error: error,
            confidence: confidence
        )
    }

    private func pauseForInterruption() {
        guard state == .listening else { return }
        bufferGate.withLock { $0 = false }
        if engine?.isRunning == true { engine?.pause() }
        state = .paused
    }

    private func resumeAfterInterruption() {
        guard state == .paused, let engine else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            try engine.start()
            bufferGate.withLock { $0 = true }
            state = .listening
            rollRecognition()
        } catch {
            Log.app.notice("dictation resume failed: \(error)")
            tearDown()
            state = .unavailable
        }
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

    @available(iOS 26.0, *)
    private static func installOnDeviceLocales() async -> Bool {
        guard SpeechTranscriber.isAvailable else { return false }
        var installed = false
        for locale in SpeechLocales.candidates {
            let resolved = await SpeechTranscriber.supportedLocale(equivalentTo: locale) ?? locale
            let transcriber = SpeechTranscriber(
                locale: resolved,
                preset: .progressiveTranscription
            )
            if await AssetInventory.status(forModules: [transcriber]) == .installed {
                installed = true
                continue
            }
            guard let request = try? await AssetInventory.assetInstallationRequest(
                supporting: [transcriber]
            ) else { continue }
            do {
                try await request.downloadAndInstall()
                installed = true
            } catch {
                Log.app.notice("dictation locale install failed: \(error)")
            }
        }
        return installed || !SpeechLocales.recognizers().isEmpty
    }
}

/// Category, mode, and options AVAudioSession actually accepts.
///
/// `duckOthers` is valid with playAndRecord, not with record. A device that
/// refuses the first plan gets the next. Live dictation and brew notes share
/// the list, so a phone, a mini, and a headset take the same path.
nonisolated struct DictationSessionPlan: Equatable, Sendable {
    var category: AVAudioSession.Category
    var mode: AVAudioSession.Mode
    var options: AVAudioSession.CategoryOptions
}

nonisolated enum DictationSession {
    static let plans: [DictationSessionPlan] = [
        DictationSessionPlan(category: .playAndRecord, mode: .measurement, options: .duckOthers),
        DictationSessionPlan(category: .record, mode: .measurement, options: []),
        DictationSessionPlan(category: .record, mode: .default, options: []),
    ]

    /// `deactivateFirst` is for a recorder that must drop the previous
    /// category. Live dictation leaves the session up so a start already
    /// in progress is not cut off.
    static func activate(deactivateFirst: Bool) throws {
        let session = AVAudioSession.sharedInstance()
        if deactivateFirst {
            try? session.setActive(false)
        }
        var lastError: Error?
        for plan in plans {
            do {
                try session.setCategory(plan.category, mode: plan.mode, options: plan.options)
                try session.setActive(true)
                return
            } catch {
                lastError = error
                Log.app.notice("audio session \(plan.category.rawValue) failed: \(error)")
            }
        }
        throw lastError ?? DictationError.unavailable
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
        return await requestMicrophone()
    }

    /// Voice notes only need the mic. Speech permission waits until transcribe.
    @concurrent
    static func requestMicrophone() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { allowed in
                continuation.resume(returning: allowed)
            }
        }
    }
}

/// Holds the live recognition request for the audio tap. The tap is not on
/// the main actor; `SFSpeechAudioBufferRecognitionRequest` is not Sendable,
/// so an unfair lock cannot wrap it.
///
/// `append` holds the lock for the whole write. `replace` takes the same
/// lock before anyone calls `endAudio`, so a buffer cannot land on a
/// request that has already ended.
nonisolated private final class RequestHolder: @unchecked Sendable {
    private var requests: [SFSpeechAudioBufferRecognitionRequest] = []
    private let lock = NSLock()

    @discardableResult
    func replace(with requests: [SFSpeechAudioBufferRecognitionRequest]) -> [SFSpeechAudioBufferRecognitionRequest] {
        lock.lock()
        let previous = self.requests
        self.requests = requests
        lock.unlock()
        return previous
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let live = requests
        for request in live {
            request.append(buffer)
        }
        lock.unlock()
    }
}

/// Speech and session callbacks capture this, not `Dictation`. The class is
/// main-actor isolated; these blocks are not.
nonisolated private final class DictationEvents: @unchecked Sendable {
    weak var owner: Dictation?

    func recognition(
        localeID: String,
        text: String?,
        isFinal: Bool,
        error: NSError?,
        confidence: Float,
        generation: Int
    ) {
        Task { @MainActor [weak owner] in
            owner?.receiveRecognition(
                localeID: localeID,
                text: text,
                isFinal: isFinal,
                error: error,
                confidence: confidence,
                generation: generation
            )
        }
    }

    func routeChanged(_ reasonValue: UInt?) {
        Task { @MainActor [weak owner] in
            owner?.receiveRouteChange(reasonValue)
        }
    }

    func interrupted(typeValue: UInt?, optionsValue: UInt?) {
        Task { @MainActor [weak owner] in
            owner?.receiveInterruption(typeValue: typeValue, optionsValue: optionsValue)
        }
    }
}

/// One microphone. Brew has a page-level Dictate and a notes field; both
/// would otherwise install a tap on the same input node.
///
/// The owner is tracked by identity so a view that vanishes without `cancel()`
/// still releases the lock from `deinit`. A foreground reaper clears a lock
/// whose owner is already gone.
nonisolated enum DictationMic {
    private static let state = MicLock()

    @discardableResult
    static func acquire(_ owner: AnyObject) -> Bool {
        state.watchForeground()
        return state.acquire(owner)
    }

    static func release(_ owner: AnyObject) {
        release(id: ObjectIdentifier(owner))
    }

    static func release(id: ObjectIdentifier) {
        state.release(id: id)
    }

    static func clearStaleOwner() {
        state.clear()
    }

    static func reapIfAbandoned() {
        state.reapIfAbandoned()
    }

    #if DEBUG
    static var isHeld: Bool {
        state.isHeld
    }

    static func resetForTests() {
        state.clear()
    }
    #endif
}

/// Mutable mic-lock state. `weak` owner is not Sendable, so the lock lives
/// in an unchecked box rather than `OSAllocatedUnfairLock`.
nonisolated private final class MicLock: @unchecked Sendable {
    private var ownerID: ObjectIdentifier?
    private weak var owner: AnyObject?
    private var foregroundObserver: (any NSObjectProtocol)?
    private let lock = NSLock()

    func acquire(_ owner: AnyObject) -> Bool {
        let id = ObjectIdentifier(owner)
        lock.lock()
        defer { lock.unlock() }
        if let ownerID, ownerID != id, self.owner != nil { return false }
        self.ownerID = id
        self.owner = owner
        return true
    }

    func release(id: ObjectIdentifier) {
        lock.lock()
        defer { lock.unlock() }
        if ownerID == id {
            ownerID = nil
            owner = nil
        }
    }

    func clear() {
        lock.lock()
        ownerID = nil
        owner = nil
        lock.unlock()
    }

    func reapIfAbandoned() {
        lock.lock()
        if owner == nil {
            ownerID = nil
        }
        lock.unlock()
    }

    func watchForeground() {
        lock.lock()
        let already = foregroundObserver != nil
        lock.unlock()
        guard !already else { return }
        let observer = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            DictationMic.reapIfAbandoned()
        }
        lock.lock()
        if foregroundObserver == nil {
            foregroundObserver = observer
        } else {
            NotificationCenter.default.removeObserver(observer)
        }
        lock.unlock()
    }

    #if DEBUG
    var isHeld: Bool {
        lock.lock()
        defer { lock.unlock() }
        return ownerID != nil
    }
    #endif
}

/// AirPods connecting, a watch taking the call, a car stereo — rebuild the
/// tap. Other reasons (our own category changes) are ignored so we do not loop.
nonisolated enum DictationRouteChange: Equatable, Sendable {
    static func shouldRebuild(_ reason: AVAudioSession.RouteChangeReason) -> Bool {
        switch reason {
        case .newDeviceAvailable, .oldDeviceUnavailable:
            return true
        default:
            return false
        }
    }
}

/// Joining spoken fragments. Isolated from the audio graph so tests can pin it.
nonisolated enum DictationTranscript {
    static func join(_ settled: String, _ live: String) -> String {
        let settled = settled.trimmingCharacters(in: .whitespacesAndNewlines)
        let live = live.trimmingCharacters(in: .whitespacesAndNewlines)
        if settled.isEmpty { return live }
        if live.isEmpty { return settled }
        return settled + " " + live
    }

    /// A finished transcript always lands after what is already in the field,
    /// with a space if both sides have content. Dictation never erases.
    static func apply(_ spoken: String, to existing: String) -> String {
        let spoken = spoken.trimmingCharacters(in: .whitespacesAndNewlines)
        let existing = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        if existing.isEmpty { return spoken }
        if spoken.isEmpty { return existing }
        return existing + " " + spoken
    }
}

/// Speech reports routine "no speech" as an error. Retry those; give up on
/// the rest after a short streak.
nonisolated enum DictationFailure: Equatable, Sendable {
    case retry
    case giveUp

    /// `kAFAssistantErrorDomain` 203 / 1110 (no speech) and 216 (cancelled).
    private static let retryCodes: Set<Int> = [203, 1110, 216]

    static func classify(_ error: Error) -> DictationFailure {
        let ns = error as NSError
        if retryCodes.contains(ns.code) { return .retry }
        if ns.domain == NSURLErrorDomain, ns.code == NSURLErrorCancelled { return .retry }
        return .giveUp
    }
}

nonisolated enum DictationError: Error {
    case unavailable
}
