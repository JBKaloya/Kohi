import Foundation
import os

/// Persists sync state between launches: which rows need pushing, which were
/// deleted, and where we left off pulling.
///
/// Tracked per `EntityKind` so a new entity needs a case and a row DTO, not a
/// second outbox. Snapshots written before that change are migrated on load.
@Observable
final class SyncOutbox {
    private(set) var dirty: [EntityKind: Set<UUID>] = [:]
    private(set) var tombstones: [EntityKind: [UUID: Date]] = [:]
    private(set) var lastPulledAt: [EntityKind: Date] = [:]
    private(set) var uploadedImages: [UUID: Set<String>] = [:]
    /// Per-entity failures that did not abort the rest of the push.
    private(set) var failures: [String: ItemFailure] = [:]

    @ObservationIgnored private let url: URL
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init() {
        let support = URL.applicationSupportDirectory
        url = support.appending(path: "sync.json", directoryHint: .notDirectory)
        load()
    }

    // MARK: - Reading

    var hasPendingWork: Bool {
        dirty.values.contains { !$0.isEmpty } || tombstones.values.contains { !$0.isEmpty }
    }

    func dirtyIDs(_ kind: EntityKind) -> Set<UUID> {
        dirty[kind] ?? []
    }

    func tombstones(_ kind: EntityKind) -> [UUID: Date] {
        tombstones[kind] ?? [:]
    }

    /// Rows waiting to be pushed, per kind. Drives the account sheet's counter,
    /// which is how you check by eye that nothing is stuck.
    var pendingCounts: [(kind: EntityKind, count: Int)] {
        EntityKind.allCases.compactMap { kind in
            let count = dirtyIDs(kind).count + tombstones(kind).count
            return count > 0 ? (kind, count) : nil
        }
    }

    var dirtyCardIDs: Set<UUID> { dirtyIDs(.card) }

    // MARK: - Writing

    func markDirty(_ kind: EntityKind, _ id: UUID) {
        dirty[kind, default: []].insert(id)
        scheduleSave()
    }

    func markDeleted(_ kind: EntityKind, _ id: UUID) {
        dirty[kind]?.remove(id)
        tombstones[kind, default: [:]][id] = .now
        if kind == .card { uploadedImages.removeValue(forKey: id) }
        scheduleSave()
    }

    func clearDirty(_ kind: EntityKind, _ id: UUID) {
        dirty[kind]?.remove(id)
        scheduleSave()
    }

    func clearTombstone(_ kind: EntityKind, _ id: UUID) {
        tombstones[kind]?.removeValue(forKey: id)
        scheduleSave()
    }

    func markImageUploaded(_ id: UUID, kind: String) {
        uploadedImages[id, default: []].insert(kind)
        scheduleSave()
    }

    func needsUpload(_ id: UUID, kind: String) -> Bool {
        !(uploadedImages[id]?.contains(kind) ?? false)
    }

    func resetImageUpload(_ id: UUID, kind: String) {
        uploadedImages[id]?.remove(kind)
        scheduleSave()
    }

    func lastPulledAt(_ kind: EntityKind) -> Date? {
        lastPulledAt[kind]
    }

    func setLastPulledAt(_ date: Date, for kind: EntityKind) {
        lastPulledAt[kind] = date
        scheduleSave()
    }

    // MARK: - Per-entity failures

    struct ItemFailure: Codable, Hashable, Sendable {
        var kind: String
        var id: UUID
        var name: String
        var message: String
        var attempts: Int
        var nextRetry: Date
    }

    func noteFailure(_ kind: EntityKind, id: UUID, name: String, message: String) {
        let key = Self.failureKey(kind, id)
        var current = failures[key] ?? ItemFailure(
            kind: kind.rawValue,
            id: id,
            name: name,
            message: message,
            attempts: 0,
            nextRetry: .now
        )
        current.attempts += 1
        current.name = name
        current.message = message
        let delay = min(pow(2.0, Double(current.attempts)), 64)
        current.nextRetry = Date.now.addingTimeInterval(delay)
        failures[key] = current
        scheduleSave()
    }

    func clearFailure(_ kind: EntityKind, _ id: UUID) {
        failures.removeValue(forKey: Self.failureKey(kind, id))
        scheduleSave()
    }

    func shouldSkip(_ kind: EntityKind, _ id: UUID) -> Bool {
        guard let failure = failures[Self.failureKey(kind, id)] else { return false }
        return failure.nextRetry > Date.now
    }

    /// One line the account sheet can name: "Brew on Kenya: FK …".
    var errorSummary: String? {
        let lines = failures.values
            .sorted { $0.name < $1.name }
            .map { "\($0.name): \($0.message)" }
        return lines.isEmpty ? nil : lines.joined(separator: " · ")
    }

    private static func failureKey(_ kind: EntityKind, _ id: UUID) -> String {
        "\(kind.rawValue):\(id.uuidString)"
    }

    func purgeStaleTombstones(olderThan days: Int = 30) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .distantPast
        for (kind, entries) in tombstones {
            tombstones[kind] = entries.filter { $0.value > cutoff }
        }
        scheduleSave()
    }

    // MARK: - Persistence

    /// Keyed by `EntityKind.rawValue` so `sync.json` stays readable, and so the
    /// legacy card-only keys can be decoded without a type clash.
    private struct Snapshot: Codable {
        var version: Int?
        var dirtyByKind: [String: Set<UUID>]?
        var tombstonesByKind: [String: [UUID: Date]]?
        var lastPulledByKind: [String: Date]?
        var uploadedImages: [UUID: Set<String>]?
        var failures: [String: ItemFailure]?

        // Written by the card-only outbox. Read once, then dropped.
        var dirtyCardIDs: Set<UUID>?
        var tombstones: [UUID: Date]?
        var lastPulledAt: Date?
    }

    private static let currentVersion = 1

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode(Snapshot.self, from: data) else { return }

        uploadedImages = snapshot.uploadedImages ?? [:]
        failures = snapshot.failures ?? [:]

        if let byKind = snapshot.dirtyByKind {
            dirty = Self.keyed(byKind)
        }
        if let byKind = snapshot.tombstonesByKind {
            tombstones = Self.keyed(byKind)
        }
        if let byKind = snapshot.lastPulledByKind {
            lastPulledAt = Self.keyed(byKind)
        }

        // Migration from the card-only snapshot: fold the flat sets into `.card`
        // without losing pending work.
        if snapshot.dirtyByKind == nil, let legacy = snapshot.dirtyCardIDs, !legacy.isEmpty {
            dirty[.card] = legacy
        }
        if snapshot.tombstonesByKind == nil, let legacy = snapshot.tombstones, !legacy.isEmpty {
            tombstones[.card] = legacy
        }
        if snapshot.lastPulledByKind == nil, let legacy = snapshot.lastPulledAt {
            lastPulledAt[.card] = legacy
        }
        if snapshot.version != Self.currentVersion {
            Log.app.info("migrated sync.json to v\(Self.currentVersion)")
            scheduleSave()
        }
    }

    private static func keyed<Value>(_ raw: [String: Value]) -> [EntityKind: Value] {
        var result: [EntityKind: Value] = [:]
        for (key, value) in raw {
            guard let kind = EntityKind(rawValue: key) else { continue }
            result[kind] = value
        }
        return result
    }

    private static func unkeyed<Value>(_ typed: [EntityKind: Value]) -> [String: Value] {
        var result: [String: Value] = [:]
        for (kind, value) in typed {
            result[kind.rawValue] = value
        }
        return result
    }

    private func snapshot() -> Snapshot {
        Snapshot(
            version: Self.currentVersion,
            dirtyByKind: Self.unkeyed(dirty.filter { !$0.value.isEmpty }),
            tombstonesByKind: Self.unkeyed(tombstones.filter { !$0.value.isEmpty }),
            lastPulledByKind: Self.unkeyed(lastPulledAt),
            uploadedImages: uploadedImages,
            failures: failures.isEmpty ? nil : failures
        )
    }

    private func write(_ snapshot: Snapshot) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = snapshot()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self.write(snapshot)
        }
    }

    func flush() {
        saveTask?.cancel()
        write(snapshot())
    }
}
