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

    /// Bundled rows, keyed by slug, so a suggestion can be sorted by how many
    /// Paris cafés serve that roaster without the count ever being shown.
    private(set) var seedBySlug: [String: RoasterSeed] = [:]

    @ObservationIgnored weak var sink: (any ArchiveChangeSink)?
    /// Called when a local seed row is replaced by the shared row for the same
    /// roastery, so cards linked to the old id can follow.
    @ObservationIgnored var onReassign: ((_ from: UUID, _ to: UUID) -> Void)?
    @ObservationIgnored private let files: JSONFileStore<Roaster>
    @ObservationIgnored private let seedStamp: JSONDocumentStore<RoasterSeedStamp>
    @ObservationIgnored private var ownShopIDs: Set<String> = []
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init(
        files: JSONFileStore<Roaster> = JSONFileStore(filename: "roasters.json"),
        seedStamp: JSONDocumentStore<RoasterSeedStamp> = JSONDocumentStore(filename: "roaster-seed-stamp.json")
    ) {
        self.files = files
        self.seedStamp = seedStamp
        roasters = files.load()
    }

    func roaster(id: UUID) -> Roaster? {
        roasters.first { $0.id == id }
    }

    /// The entry a free-text roaster name belongs to, if the index knows it.
    /// Country narrows it when the card says one; without it, a unique name
    /// match is good enough.
    func roaster(seedID: String) -> Roaster? {
        roasters.first { $0.seedID == seedID }
    }

    /// A served-roaster id is a seed slug, or the UUID of a roaster the person
    /// added themselves.
    func roaster(servedID: String) -> Roaster? {
        if let seeded = roaster(seedID: servedID) { return seeded }
        guard let id = UUID(uuidString: servedID) else { return nil }
        return roaster(id: id)
    }

    func match(name: String, country: String = "") -> Roaster? {
        let folded = Roaster.fold(name)
        guard !folded.isEmpty else { return nil }
        if !country.isEmpty {
            let probe = Roaster(name: name, country: country)
            if let exact = roasters.first(where: { $0.dedupeKey == probe.dedupeKey }) {
                return exact
            }
            let countryFold = Roaster.fold(country)
            let narrowed = roasters.filter {
                nameMatches($0, folded: folded) && Roaster.fold($0.country) == countryFold
            }
            if narrowed.count == 1 { return narrowed.first }
        }
        let byName = roasters.filter { nameMatches($0, folded: folded) }
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
            if aliasFolds(of: roaster).contains(where: { $0 == folded || $0.hasPrefix(folded) }) {
                return (roaster, 1)
            }
            return nil
        }
        return scored
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
                let leftServed = shopsServed(lhs.0)
                let rightServed = shopsServed(rhs.0)
                if leftServed != rightServed { return leftServed > rightServed }
                return lhs.0.name.localizedCompare(rhs.0.name) == .orderedAscending
            }
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
        // No country typed: a unique roaster by that name is the one meant.
        // With two countries on the table, homonyms stay apart.
        if roaster.country.isEmpty, let existing = match(name: roaster.name) {
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
        updated.editedByUser = true
        updated.seedID = roasters[index].seedID
        roasters[index] = updated
        sink?.changed(.roaster, id: roaster.id)
        scheduleSave()
    }

    /// Marks a roaster for the shared table. Seed rows are not pushed when the
    /// extract is applied — only once a card actually links one, which is what
    /// the foreign key on `coffee_cards.roaster_id` requires.
    func publish(_ id: UUID) {
        sink?.changed(.roaster, id: id)
    }

    /// Fills the index from the bundled extract. Idempotent, and skipped when
    /// this `fetchedAt` is already applied and every slug is present.
    ///
    /// An existing row keeps its id. Empty website, Instagram, city and country
    /// are filled; a value someone typed is left alone. Nothing is pushed.
    func applySeed(_ seeds: [RoasterSeed]) {
        seedBySlug = Dictionary(uniqueKeysWithValues: seeds.map { ($0.slug, $0) })
        ownShopIDs = Set(seeds.flatMap(\.ownShopIDs))

        let fetchedAt = seeds.map(\.fetchedAt).filter { !$0.isEmpty }.max() ?? ""
        let present = Set(roasters.compactMap(\.seedID))
        if !fetchedAt.isEmpty,
           seedStamp.load()?.fetchedAt == fetchedAt,
           seeds.allSatisfy({ present.contains($0.slug) }) {
            return
        }

        var changed = false
        for seed in seeds {
            let located = locate(seed)
            if located.ambiguous { continue }
            if let index = located.index {
                if absorb(seed, into: index) { changed = true }
            } else {
                roasters.append(makeRoaster(from: seed))
                changed = true
            }
        }
        if changed {
            roasters.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
            scheduleSave()
        }
        if !fetchedAt.isEmpty {
            try? seedStamp.save(RoasterSeedStamp(fetchedAt: fetchedAt))
        }
    }

    /// True when one of this roaster's own Paris shops is `placeID`.
    func ownsShop(_ placeID: String) -> Bool {
        ownShopIDs.contains(placeID)
    }

    func shopsServed(_ roaster: Roaster) -> Int {
        guard let seedID = roaster.seedID else { return 0 }
        return seedBySlug[seedID]?.parisShopsServed ?? 0
    }

    /// Where the row came from. A correction by the person using the app wins.
    func provenance(of roaster: Roaster) -> String? {
        if roaster.editedByUser { return Copy.fromYou }
        guard let seedID = roaster.seedID, let seed = seedBySlug[seedID] else {
            return roaster.createdBy == nil ? nil : Copy.fromYou
        }
        if seed.sources.contains("specialtyCoffeeParis") {
            return Copy.fromSpecialtyCoffeeParis(seed.fetchedAt)
        }
        if seed.sources.contains("annexeD") {
            return Copy.fromKohiSeed
        }
        return nil
    }

    /// Applies rows from the shared table. Remote wins on ties: this is an
    /// index everyone reads, and a local edit that lost the race is a lot less
    /// costly than two divergent copies of the same roastery.
    func merge(_ incoming: [Roaster]) {
        guard !incoming.isEmpty else { return }
        var byID = Dictionary(roasters.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var reassigned: [(from: UUID, to: UUID)] = []
        for roaster in incoming {
            guard let local = byID[roaster.id] else {
                // Someone else filed this roastery before this device applied
                // the seed. The shared row wins; the local seed copy goes, and
                // any card pointing at it is moved over.
                if let twin = seedTwin(of: roaster, in: byID) {
                    var adopted = roaster
                    adopted.seedID = twin.seedID
                    byID.removeValue(forKey: twin.id)
                    byID[roaster.id] = adopted
                    reassigned.append((twin.id, roaster.id))
                    continue
                }
                byID[roaster.id] = roaster
                continue
            }
            if local.updatedAt > roaster.updatedAt { continue }
            var merged = roaster
            // The shared row has neither field. Keep what this device knows.
            merged.seedID = roaster.seedID ?? local.seedID
            merged.editedByUser = local.editedByUser || roaster.editedByUser
            byID[roaster.id] = merged
        }
        roasters = byID.values.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        scheduleSave()
        for pair in reassigned {
            onReassign?(pair.from, pair.to)
        }
    }

    /// A seed row this device created and nobody has corrected, that names the
    /// same roastery as `remote`: same website, or same name or alias with a
    /// compatible country.
    private func seedTwin(of remote: Roaster, in byID: [UUID: Roaster]) -> Roaster? {
        guard remote.seedID == nil else { return nil }
        let remoteName = Roaster.fold(remote.name)
        let remoteCountry = Roaster.fold(remote.country)
        let hits = byID.values.filter { local in
            guard let seedID = local.seedID,
                  local.createdBy == nil,
                  !local.editedByUser,
                  local.id == RoasterSeed.stableUUID(slug: seedID)
            else { return false }
            if let host = remote.websiteDomain, host == local.websiteDomain { return true }
            let localCountry = Roaster.fold(local.country)
            let countryFits = remote.country.isEmpty || local.country.isEmpty || remoteCountry == localCountry
            return countryFits && nameMatches(local, folded: remoteName)
        }
        return hits.count == 1 ? hits.first : nil
    }

    private func nameMatches(_ roaster: Roaster, folded: String) -> Bool {
        Roaster.fold(roaster.name) == folded || aliasFolds(of: roaster).contains(folded)
    }

    private func aliasFolds(of roaster: Roaster) -> Set<String> {
        guard let seedID = roaster.seedID, let seed = seedBySlug[seedID] else { return [] }
        return Set(seed.aliases.map(Roaster.fold))
    }

    /// seed id, then website domain, then a unique folded name or alias.
    /// Country is ignored: a "Lomi" typed with no country is still Lomi.
    /// Two homonyms are left alone rather than filed as a third copy.
    private func locate(_ seed: RoasterSeed) -> (index: Int?, ambiguous: Bool) {
        if let index = roasters.firstIndex(where: { $0.seedID == seed.slug }) {
            return (index, false)
        }
        if let host = seed.websiteDomain {
            let hits = roasters.indices.filter { roasters[$0].websiteDomain == host }
            if hits.count == 1 { return (hits[0], false) }
            if hits.count > 1 { return (nil, true) }
        }
        let keys = Set(([seed.name] + seed.aliases).map(Roaster.fold).filter { !$0.isEmpty })
        let hits = roasters.indices.filter { keys.contains(Roaster.fold(roasters[$0].name)) }
        if hits.count == 1 { return (hits[0], false) }
        if hits.count > 1 { return (nil, true) }
        return (nil, false)
    }

    /// Fills only what is blank. Returns whether the row changed.
    private func absorb(_ seed: RoasterSeed, into index: Int) -> Bool {
        var current = roasters[index]
        var changed = false
        if current.seedID != seed.slug {
            current.seedID = seed.slug
            changed = true
        }
        if (current.website ?? "").isEmpty, let website = seed.website, !website.isEmpty {
            current.website = website
            changed = true
        }
        if (current.instagram ?? "").isEmpty, let instagram = seed.instagram, !instagram.isEmpty {
            current.instagram = instagram
            changed = true
        }
        if current.city.isEmpty, !seed.city.isEmpty {
            current.city = seed.city
            changed = true
        }
        if current.country.isEmpty, !seed.country.isEmpty {
            current.country = seed.country
            changed = true
        }
        if changed { roasters[index] = current }
        return changed
    }

    private func makeRoaster(from seed: RoasterSeed) -> Roaster {
        Roaster(
            id: RoasterSeed.stableUUID(slug: seed.slug),
            name: seed.name,
            country: seed.country,
            city: seed.city,
            website: seed.website,
            instagram: seed.instagram,
            createdBy: nil,
            updatedAt: RoasterSeed.stamped(seed.fetchedAt),
            seedID: seed.slug,
            editedByUser: false
        )
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
