import Foundation
import Observation
import os
import Supabase

/// The roaster index: shared, read-mostly, and cached on disk so suggestions
/// work offline.
///
/// A card's free-text `roaster` stays authoritative for display. This store
/// only adds the ability to say "these two cards are the same roastery", which
/// is what makes an index out of a pile.
@Observable
final class RoasterStore {
    private(set) var roasters: [Roaster] = []

    @ObservationIgnored weak var sink: (any ArchiveChangeSink)?
    @ObservationIgnored private let files: JSONFileStore<Roaster>
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init(files: JSONFileStore<Roaster> = JSONFileStore(filename: "roasters.json")) {
        self.files = files
        roasters = files.load()
    }

    func roaster(id: UUID) -> Roaster? {
        roasters.first { $0.id == id }
    }

    /// The entry a free-text roaster name belongs to, if the index knows it.
    /// Country narrows it when the card says one; without it, a unique name
    /// match is good enough.
    func match(name: String, country: String = "") -> Roaster? {
        let probe = Roaster(name: name, country: country)
        if !country.isEmpty,
           let exact = roasters.first(where: { $0.dedupeKey == probe.dedupeKey }) {
            return exact
        }
        let folded = Roaster.fold(name)
        guard !folded.isEmpty else { return nil }
        let byName = roasters.filter { Roaster.fold($0.name) == folded }
        return byName.count == 1 ? byName.first : nil
    }

    /// Suggestions under the roaster field. Prefix matches first: typing
    /// "bell" should offer Belleville before "Cafés de Belleville".
    func suggestions(for query: String, limit: Int = 4) -> [Roaster] {
        let folded = Roaster.fold(query)
        guard folded.count >= 2 else { return [] }
        let scored = roasters.compactMap { roaster -> (Roaster, Int)? in
            let candidate = Roaster.fold(roaster.name)
            if candidate == folded { return (roaster, 0) }
            if candidate.hasPrefix(folded) { return (roaster, 1) }
            if candidate.contains(folded) { return (roaster, 2) }
            return nil
        }
        return scored
            .sorted { ($0.1, $0.0.name) < ($1.1, $1.0.name) }
            .prefix(limit)
            .map(\.0)
    }

    /// Adds a roaster, or returns the existing entry when it is the same one.
    /// Creating a near-duplicate is the failure mode that makes a shared index
    /// worthless, so the check happens here rather than in the form.
    @discardableResult
    func add(_ roaster: Roaster) -> Roaster {
        if let existing = roasters.first(where: { $0.dedupeKey == roaster.dedupeKey }) {
            return existing
        }
        roasters.append(roaster)
        roasters.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
        sink?.changed(.roaster, id: roaster.id)
        scheduleSave()
        return roaster
    }

    func update(_ roaster: Roaster) {
        guard let index = roasters.firstIndex(where: { $0.id == roaster.id }) else { return }
        var updated = roaster
        updated.updatedAt = .now
        roasters[index] = updated
        sink?.changed(.roaster, id: roaster.id)
        scheduleSave()
    }

    /// Applies rows from the shared table. Remote wins on ties: this is an
    /// index everyone reads, and a local edit that lost the race is a lot less
    /// costly than two divergent copies of the same roastery.
    func merge(_ incoming: [Roaster]) {
        guard !incoming.isEmpty else { return }
        var byID = Dictionary(roasters.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for roaster in incoming {
            if let local = byID[roaster.id], local.updatedAt > roaster.updatedAt { continue }
            byID[roaster.id] = roaster
        }
        roasters = byID.values.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        scheduleSave()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = roasters
        let files = files
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await Task.detached(priority: .utility) {
                do { try files.save(snapshot) } catch {
                    Log.app.error("roaster save failed: \(error)")
                }
            }.value
        }
    }

    func flush() {
        saveTask?.cancel()
        try? files.save(roasters)
    }
}

extension RoasterStore: RemoteSyncStore {
    var syncKinds: [EntityKind] { [.roaster] }

    func syncableIDs(_ kind: EntityKind) -> [UUID] {
        kind == .roaster ? roasters.map(\.id) : []
    }

    /// Roasters are never deleted from a client: the entry is shared, and
    /// another archive may be pointing at it. Tombstones are dropped.
    func pushRecords(
        _ kind: EntityKind,
        ids: Set<UUID>,
        deleted: Set<UUID>,
        client: SupabaseClient,
        userID: UUID
    ) async throws {
        let rows = roasters
            .filter { ids.contains($0.id) }
            .map { RoasterRow(roaster: $0, userID: userID) }
        guard !rows.isEmpty else { return }
        try await client.from(EntityKind.roaster.table).upsert(rows).execute()
    }

    func pullRecords(
        _ kind: EntityKind,
        since: Date?,
        client: SupabaseClient,
        userID: UUID
    ) async throws {
        var query = client.from(EntityKind.roaster.table).select()
        if let since {
            query = query.gt("updated_at", value: since.ISO8601Format())
        }
        let rows: [RoasterRow] = try await query.execute().value
        merge(rows.map { $0.toRoaster() })
    }
}
