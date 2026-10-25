import Foundation
import Observation
import os
import Supabase

/// Coffee-shop tastings, in `tastings.json` beside the archive.
///
/// Deletes are soft: a deleted tasting keeps its row with `deletedAt` set, so
/// the legacy copy still nested in its card is never imported a second time,
/// on this device or any other.
@Observable
final class TastingStore {
    /// Everything, deleted included. Views read `tastings`.
    private(set) var all: [Tasting] = []

    @ObservationIgnored weak var sink: (any ArchiveChangeSink)?
    @ObservationIgnored private let files: JSONFileStore<Tasting>
    @ObservationIgnored private let ledgerFile: JSONDocumentStore<TastingLedger>
    @ObservationIgnored private(set) var ledger: TastingLedger
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init(
        files: JSONFileStore<Tasting> = JSONFileStore(filename: "tastings.json"),
        ledgerFile: JSONDocumentStore<TastingLedger> = JSONDocumentStore(filename: "tastings-ledger.json")
    ) {
        self.files = files
        self.ledgerFile = ledgerFile
        all = Self.sorted(files.load())
        ledger = ledgerFile.load() ?? TastingLedger()
        ledger.imported.formUnion(all.map(\.id))
    }

    /// Alive tastings, newest first.
    var tastings: [Tasting] { all.filter { !$0.isDeleted } }

    var isEmpty: Bool { !all.contains { !$0.isDeleted } }

    func tasting(id: UUID) -> Tasting? {
        all.first { $0.id == id && !$0.isDeleted }
    }

    func tastings(forCard cardID: UUID) -> [Tasting] {
        tastings.filter { $0.cardID == cardID }
    }

    /// Whether an id was ever held here, alive or deleted, or imported.
    func knows(_ id: UUID) -> Bool {
        ledger.imported.contains(id)
    }

    @discardableResult
    func add(_ tasting: Tasting) -> Tasting {
        var new = tasting
        new.updatedAt = .now
        all = Self.sorted(all.filter { $0.id != new.id } + [new])
        ledger.imported.insert(new.id)
        ledger.insertOnly.remove(new.id)
        sink?.changed(.tasting, id: new.id)
        scheduleSave()
        return new
    }

    func update(_ tasting: Tasting) {
        guard let index = all.firstIndex(where: { $0.id == tasting.id }) else { return }
        var updated = tasting
        updated.updatedAt = .now
        all[index] = updated
        all = Self.sorted(all)
        ledger.insertOnly.remove(tasting.id)
        sink?.changed(.tasting, id: tasting.id)
        scheduleSave()
    }

    /// Soft delete: the row travels as a tombstone.
    func delete(_ tasting: Tasting) {
        guard let index = all.firstIndex(where: { $0.id == tasting.id }) else { return }
        let now = Date.now
        all[index].deletedAt = now
        all[index].updatedAt = now
        ledger.insertOnly.remove(tasting.id)
        sink?.changed(.tasting, id: tasting.id)
        scheduleSave()
    }

    /// A deleted card leaves its tastings intact, only unlinked.
    func unlinkCard(_ cardID: UUID) {
        var changed: [UUID] = []
        for index in all.indices where all[index].cardID == cardID {
            all[index].cardID = nil
            all[index].updatedAt = .now
            changed.append(all[index].id)
        }
        guard !changed.isEmpty else { return }
        for id in changed {
            ledger.insertOnly.remove(id)
            sink?.changed(.tasting, id: id)
        }
        scheduleSave()
    }

    /// Adds tastings lifted from cards. Ids already known are skipped, so this
    /// is safe to call as often as cards arrive. Imports are pushed insert-only:
    /// a row the server already has, alive or deleted, wins over them.
    @discardableResult
    func importLegacy(_ imported: [Tasting]) -> Int {
        let fresh = imported.filter { !ledger.imported.contains($0.id) }
        guard !fresh.isEmpty else { return 0 }
        all = Self.sorted(all + fresh)
        for tasting in fresh {
            ledger.imported.insert(tasting.id)
            ledger.insertOnly.insert(tasting.id)
            sink?.changed(.tasting, id: tasting.id)
        }
        scheduleSave()
        return fresh.count
    }

    /// Ids imported from a card that nobody has touched since. Pushed with
    /// insert-only semantics.
    func isInsertOnly(_ id: UUID) -> Bool {
        ledger.insertOnly.contains(id)
    }

    /// Last write wins per record, by `updatedAt`. Tombstones merge like any
    /// other row, which is what stops a deleted tasting from coming back.
    func merge(_ incoming: [Tasting]) {
        guard !incoming.isEmpty else { return }
        var byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for tasting in incoming {
            ledger.imported.insert(tasting.id)
            ledger.insertOnly.remove(tasting.id)
            if let local = byID[tasting.id], local.updatedAt > tasting.updatedAt { continue }
            byID[tasting.id] = tasting
        }
        all = Self.sorted(Array(byID.values))
        scheduleSave()
    }

    private static func sorted(_ tastings: [Tasting]) -> [Tasting] {
        tastings.sorted { $0.date > $1.date }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = all
        let ledger = ledger
        let files = files
        let ledgerFile = ledgerFile
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await Task.detached(priority: .utility) {
                do {
                    try files.save(snapshot)
                    try ledgerFile.save(ledger)
                } catch {
                    Log.app.error("tasting save failed: \(error)")
                }
            }.value
        }
    }

    func flush() {
        saveTask?.cancel()
        try? files.save(all)
        try? ledgerFile.save(ledger)
    }
}

/// Which tasting ids this device has ever held, so a legacy import is a
/// one-time event per id.
nonisolated struct TastingLedger: Codable, Hashable, Sendable {
    var imported: Set<UUID> = []
    /// Imported and untouched since: pushed without overwriting the server.
    var insertOnly: Set<UUID> = []
}

extension TastingStore: RemoteSyncStore {
    var syncKinds: [EntityKind] { [.tasting] }

    func syncableIDs(_ kind: EntityKind) -> [UUID] {
        kind == .tasting ? all.map(\.id) : []
    }

    /// Rows split in two: the ones you wrote overwrite the server; the ones
    /// lifted from a card only insert, so they can never undo an edit or a
    /// delete another device already pushed. Deletes travel as tombstone rows.
    func pushRecords(
        _ kind: EntityKind,
        ids: Set<UUID>,
        deleted: Set<UUID>,
        client: SupabaseClient,
        userID: UUID
    ) async throws {
        guard kind == .tasting else { return }
        let rows = all
            .filter { ids.contains($0.id) || deleted.contains($0.id) }
            .map { TastingRow(tasting: $0, userID: userID) }
        let inserts = rows.filter { isInsertOnly($0.id) }
        let writes = rows.filter { !isInsertOnly($0.id) }
        if !writes.isEmpty {
            try await client.from(kind.table).upsert(writes).execute()
        }
        if !inserts.isEmpty {
            try await client.from(kind.table)
                .upsert(inserts, onConflict: "id", ignoreDuplicates: true)
                .execute()
        }
    }

    func pullRecords(
        _ kind: EntityKind,
        since: Date?,
        client: SupabaseClient,
        userID: UUID
    ) async throws {
        guard kind == .tasting else { return }
        var query = client.from(kind.table).select().eq("user_id", value: userID)
        if let since {
            query = query.gt("updated_at", value: since.ISO8601Format())
        }
        let rows: [TastingRow] = try await query.execute().value
        merge(rows.map { $0.toTasting() })
    }
}
