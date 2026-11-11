import Foundation
import Observation
import os
import Supabase

/// Brews logged before their coffee was chosen, in `loose-brews.json`.
///
/// They never show in the grid and are never removed on their own: they wait
/// in the brew log until a coffee is added. Linking moves the brew onto the
/// card, where it syncs with the card's brews, and out of here.
@Observable
final class LooseBrewStore {
    private(set) var brews: [Brew] = []

    @ObservationIgnored weak var sink: (any ArchiveChangeSink)?
    /// True while a local change to that id has not reached the server, so a
    /// pull does not undo it. Set by the coordinator.
    @ObservationIgnored var isPending: (UUID) -> Bool = { _ in false }
    @ObservationIgnored private let files: JSONFileStore<Brew>
    @ObservationIgnored private let ledgerFile: JSONDocumentStore<LooseBrewLedger>
    @ObservationIgnored private(set) var ledger: LooseBrewLedger
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init(
        files: JSONFileStore<Brew> = JSONFileStore(filename: "loose-brews.json"),
        ledgerFile: JSONDocumentStore<LooseBrewLedger> = JSONDocumentStore(filename: "loose-brews-ledger.json")
    ) {
        self.files = files
        self.ledgerFile = ledgerFile
        brews = Self.sorted(files.load())
        ledger = ledgerFile.load() ?? LooseBrewLedger()
    }

    var isEmpty: Bool { brews.isEmpty }

    func brew(id: UUID) -> Brew? {
        brews.first { $0.id == id }
    }

    /// Adds or replaces, by id.
    func save(_ brew: Brew) {
        brews = Self.sorted(brews.filter { $0.id != brew.id } + [brew])
        sink?.changed(.looseBrew, id: brew.id)
        scheduleSave()
    }

    func delete(_ brew: Brew) {
        guard brews.contains(where: { $0.id == brew.id }) else { return }
        brews.removeAll { $0.id == brew.id }
        sink?.deleted(.looseBrew, id: brew.id)
        scheduleSave()
    }

    /// Moves the brew onto the card. No tombstone: the row stays on the
    /// server and the card's push gives it its `card_id`.
    @discardableResult
    func link(_ brewID: UUID, to cardID: UUID, in store: CardStore) -> Bool {
        guard var brew = brew(id: brewID), var card = store.card(id: cardID) else { return false }
        brew.coffee = nil
        card.brews.removeAll { $0.id == brew.id }
        card.brews.insert(brew, at: 0)
        card.brews.sort { $0.date > $1.date }
        brews.removeAll { $0.id == brewID }
        ledger.confirmed.remove(brewID)
        store.update(card)
        scheduleSave()
        return true
    }

    /// Last write wins against the server, unless this device has a change
    /// still on its way.
    func merge(_ incoming: [Brew]) {
        guard !incoming.isEmpty else { return }
        var byID = Dictionary(brews.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for brew in incoming {
            ledger.confirmed.insert(brew.id)
            if byID[brew.id] != nil, isPending(brew.id) { continue }
            byID[brew.id] = brew
        }
        brews = Self.sorted(Array(byID.values))
        scheduleSave()
    }

    /// Drops brews another device linked to a card, or deleted. Only ids the
    /// server once confirmed count as gone, so a brew logged offline stays.
    func reconcile(linked: Set<UUID>, present: Set<UUID>) {
        let gone = brews.filter { brew in
            guard !isPending(brew.id) else { return false }
            return linked.contains(brew.id)
                || (ledger.confirmed.contains(brew.id) && !present.contains(brew.id))
        }
        guard !gone.isEmpty else { return }
        let ids = Set(gone.map(\.id))
        brews.removeAll { ids.contains($0.id) }
        ledger.confirmed.subtract(ids)
        scheduleSave()
    }

    func markConfirmed(_ id: UUID) {
        guard ledger.confirmed.insert(id).inserted else { return }
        scheduleSave()
    }

    private static func sorted(_ brews: [Brew]) -> [Brew] {
        brews.sorted { $0.date > $1.date }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = brews
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
                    Log.app.error("loose brew save failed: \(error)")
                }
            }.value
        }
    }

    func flush() {
        saveTask?.cancel()
        try? files.save(brews)
        try? ledgerFile.save(ledger)
    }
}

/// Ids the server has acknowledged, so a missing row reads as a delete
/// rather than as a brew that never left this phone.
nonisolated struct LooseBrewLedger: Codable, Hashable, Sendable {
    var confirmed: Set<UUID> = []
}

extension LooseBrewStore: RemoteSyncStore {
    var syncKinds: [EntityKind] { [.looseBrew] }

    func syncableIDs(_ kind: EntityKind) -> [UUID] {
        kind == .looseBrew ? brews.map(\.id) : []
    }

    func pushRecords(
        _ kind: EntityKind,
        ids: Set<UUID>,
        deleted: Set<UUID>,
        client: SupabaseClient,
        userID: UUID
    ) async throws {
        guard kind == .looseBrew else { return }
        let rows = brews
            .filter { ids.contains($0.id) }
            .map { brew -> BrewRow in
                var brew = brew
                brew.dropOrphanRecipeLink()
                return BrewRow(brew: brew, cardID: nil, userID: userID)
            }
        if !rows.isEmpty {
            try await client.from(kind.table).upsert(rows).execute()
            for row in rows { markConfirmed(row.id) }
        }
        if !deleted.isEmpty {
            // Never a card's brew: a linked one has its card_id by now.
            try await client.from(kind.table)
                .delete()
                .in("id", values: deleted.map(\.uuidString))
                .is("card_id", value: nil)
                .execute()
        }
    }

    func pullRecords(
        _ kind: EntityKind,
        since: Date?,
        client: SupabaseClient,
        userID: UUID
    ) async throws {
        guard kind == .looseBrew else { return }
        var query = client.from(kind.table)
            .select()
            .eq("user_id", value: userID)
            .is("card_id", value: nil)
        if let since {
            query = query.gt("updated_at", value: since.ISO8601Format())
        }
        let rows: [BrewRow] = try await query.execute().value
        merge(rows.map { $0.toBrew() })

        let local = brews.map(\.id)
        guard !local.isEmpty else { return }
        let states: [LooseBrewState] = try await client.from(kind.table)
            .select("id, card_id")
            .eq("user_id", value: userID)
            .in("id", values: local.map(\.uuidString))
            .execute()
            .value
        reconcile(
            linked: Set(states.filter { $0.card_id != nil }.map(\.id)),
            present: Set(states.map(\.id))
        )
    }
}

private struct LooseBrewState: Decodable {
    let id: UUID
    let card_id: UUID?
}
