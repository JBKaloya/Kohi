import Foundation
import os

/// Where a dictation was made.
nonisolated enum DictationContext: String, Codable, Sendable {
    case live
    case afterBrew = "after_brew"
}

/// One brew dictation, kept so the parser can be improved from real ones:
/// the audio, what Speech heard, what the parser read, and what the brewer
/// kept in the end.
nonisolated struct DictationRecord: Codable, Equatable, Identifiable, Sendable {
    struct Phrase: Codable, Equatable, Sendable {
        var at: Double
        var text: String
    }

    /// What the parser read, before anyone corrected it.
    struct Parsed: Codable, Equatable, Sendable {
        var steps: [SpokenBrewParser.TimedStep] = []
        var dose: Double?
        var water: Double?
        var beverage: Double?
        var seconds: Int?
        var temperature: Double?
        var grind: String?
        var rating: Int?
        var flavors: [String] = []
        var leftover: String = ""
        var confidence: Double = 0
        /// What the model heard in the same audio, when it was asked.
        var modelSteps: [SpokenBrewParser.TimedStep]?
        var model: String?

        init(steps: [SpokenBrewParser.TimedStep] = [], result: SpokenBrewParser.Result? = nil) {
            self.steps = steps
            guard let result else { return }
            dose = result.dose
            water = result.water
            beverage = result.beverage
            seconds = result.seconds
            temperature = result.temperature
            grind = result.grind
            rating = result.rating
            flavors = result.flavors
            leftover = result.leftover
            confidence = result.confidence
        }
    }

    var id: UUID
    var brewID: UUID?
    var recipeID: UUID?
    var context: DictationContext
    var duration: Double
    var transcript: String
    var phrases: [Phrase]
    var parsed: Parsed
    var editedSteps: [SpokenBrewParser.TimedStep]?
    var appBuild: String
    var createdAt: Date
    var audioUploaded = false
    var rowSent = false
    var editsPending = false
}

/// The row in `public.dictations`.
nonisolated struct DictationRow: Encodable, Sendable {
    let id: UUID
    let userID: UUID
    let brewID: UUID?
    let recipeID: UUID?
    let context: String
    let audioPath: String
    let durationS: Double
    let locale: String?
    let transcript: String
    let phrases: [DictationRecord.Phrase]
    let parsed: DictationRecord.Parsed
    let stepsHeard: Int
    let editedSteps: [SpokenBrewParser.TimedStep]?
    let appBuild: String
    let createdAt: Date

    init(record: DictationRecord, userID: UUID) {
        id = record.id
        self.userID = userID
        brewID = record.brewID
        recipeID = record.recipeID
        context = record.context.rawValue
        audioPath = DictationArchive.remotePath(userID: userID, id: record.id)
        durationS = record.duration
        locale = nil
        transcript = record.transcript
        phrases = record.phrases
        parsed = record.parsed
        stepsHeard = record.parsed.steps.count
        editedSteps = record.editedSteps
        appBuild = record.appBuild
        createdAt = record.createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case brewID = "brew_id"
        case recipeID = "recipe_id"
        case context
        case audioPath = "audio_path"
        case durationS = "duration_s"
        case locale
        case transcript
        case phrases
        case parsed
        case stepsHeard = "steps_heard"
        case editedSteps = "edited_steps"
        case appBuild = "app_build"
        case createdAt = "created_at"
    }
}

nonisolated struct DictationEditsPatch: Encodable, Sendable {
    let editedSteps: [SpokenBrewParser.TimedStep]

    enum CodingKeys: String, CodingKey {
        case editedSteps = "edited_steps"
    }
}

/// The outbox of dictations waiting for Supabase. Files, so a dictation made
/// offline or before sign-in still goes up later. Nothing is written when
/// sharing is off.
@MainActor
final class DictationArchive {
    static let shared = DictationArchive()

    static let bucket = "dictations"
    /// How long a sent record waits for the steps the brewer kept.
    static let editsWindow: TimeInterval = 7 * 24 * 3600

    let directory: URL
    /// Set by sync: something new is waiting.
    var onChange: (() -> Void)?

    init(directory: URL = DictationArchive.defaultDirectory) {
        self.directory = directory
    }

    nonisolated static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "dictations-outbox", directoryHint: .isDirectory)
    }

    nonisolated static func remotePath(userID: UUID, id: UUID) -> String {
        "\(userID.uuidString.lowercased())/\(id.uuidString.lowercased()).m4a"
    }

    nonisolated static var appBuild: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    // MARK: - Writing

    /// Copies the recording while it still exists. Returns the id the
    /// record will carry, or nil when sharing is off or the copy failed.
    func stash(audio: URL, sharing: Bool) -> UUID? {
        guard sharing else { return nil }
        let id = UUID()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: audio, to: audioURL(id))
            #if DEBUG
            DictationShelf.keep(audio: audio, id: id)
            #endif
            return id
        } catch {
            Log.app.notice("dictation stash failed: \(error)")
            return nil
        }
    }

    /// Writes what was heard next to the stashed audio. Called even when
    /// nothing was understood: those are the dictations to learn most from.
    func record(
        id: UUID?,
        outcome: VoiceNoteTranscriber.Outcome,
        transcript: String? = nil,
        context: DictationContext,
        brewID: UUID?,
        recipeID: UUID?,
        parsed: DictationRecord.Parsed
    ) {
        guard let id else { return }
        let record = DictationRecord(
            id: id,
            brewID: brewID,
            recipeID: recipeID,
            context: context,
            duration: outcome.duration,
            transcript: transcript ?? outcome.text,
            phrases: outcome.phrases.map { DictationRecord.Phrase(at: $0.at, text: $0.text) },
            parsed: parsed,
            appBuild: Self.appBuild,
            createdAt: .now
        )
        write(record)
        #if DEBUG
        DictationShelf.keep(record: record)
        #endif
        onChange?()
    }

    /// The steps the brewer kept, once the brew is saved.
    func keep(editedSteps: [SpokenBrewParser.TimedStep], brewID: UUID) {
        var touched = false
        for var record in pending() where record.brewID == brewID {
            record.editedSteps = editedSteps
            record.editsPending = record.rowSent
            write(record)
            touched = true
        }
        if touched { onChange?() }
    }

    // MARK: - Reading

    func pending() -> [DictationRecord] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else { return [] }
        let decoder = JSONDecoder()
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(DictationRecord.self, from: Data(contentsOf: $0)) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func audioURL(_ id: UUID) -> URL {
        directory.appending(path: "\(id.uuidString).m4a")
    }

    func manifestURL(_ id: UUID) -> URL {
        directory.appending(path: "\(id.uuidString).json")
    }

    // MARK: - Sent

    func markAudioUploaded(_ id: UUID) {
        try? FileManager.default.removeItem(at: audioURL(id))
        update(id) { $0.audioUploaded = true }
    }

    func markRowSent(_ id: UUID) {
        update(id) {
            $0.rowSent = true
            $0.editsPending = false
        }
    }

    func markEditsSent(_ id: UUID) {
        update(id) { $0.editsPending = false }
    }

    /// Done once the audio and the row are up, and either the kept steps
    /// went with them or there has been a week to send them.
    func isFinished(_ record: DictationRecord, now: Date = .now) -> Bool {
        guard record.audioUploaded, record.rowSent, !record.editsPending else { return false }
        return record.editedSteps != nil || now.timeIntervalSince(record.createdAt) > Self.editsWindow
    }

    func removeFinished(now: Date = .now) {
        for record in pending() where isFinished(record, now: now) {
            try? FileManager.default.removeItem(at: manifestURL(record.id))
            try? FileManager.default.removeItem(at: audioURL(record.id))
        }
    }

    // MARK: - Files

    private func update(_ id: UUID, _ change: (inout DictationRecord) -> Void) {
        guard let data = try? Data(contentsOf: manifestURL(id)),
              var record = try? JSONDecoder().decode(DictationRecord.self, from: data)
        else { return }
        change(&record)
        write(record)
    }

    private func write(_ record: DictationRecord) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(record)
            try data.write(to: manifestURL(record.id), options: .atomic)
        } catch {
            Log.app.notice("dictation manifest failed: \(error)")
        }
    }
}

#if DEBUG
/// The last few dictations, audio and manifest, kept on the phone after the
/// outbox has sent and deleted them, so they can be shared from Developer.
nonisolated enum DictationShelf {
    static let limit = 5

    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "dictations-shelf", directoryHint: .isDirectory)
    }

    static func keep(audio: URL, id: UUID) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? FileManager.default.copyItem(at: audio, to: directory.appending(path: "\(id.uuidString).m4a"))
        trim()
    }

    static func keep(record: DictationRecord) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(record) else { return }
        try? data.write(to: directory.appending(path: "\(record.id.uuidString).json"), options: .atomic)
    }

    static func files() -> [URL] {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? []
        return urls.sorted { date($0) > date($1) }
    }

    private static func trim() {
        let audio = files().filter { $0.pathExtension == "m4a" }
        for old in audio.dropFirst(limit) {
            try? FileManager.default.removeItem(at: old)
            try? FileManager.default.removeItem(at: old.deletingPathExtension().appendingPathExtension("json"))
        }
    }

    private static func date(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}
#endif
