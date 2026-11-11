import Foundation
import Observation
import os
import Supabase

@Observable
final class SyncCoordinator: ArchiveChangeSink {
    private(set) var isSyncing = false
    private(set) var lastSyncDate: Date?
    private(set) var lastError: String?

    @ObservationIgnored let outbox: SyncOutbox
    @ObservationIgnored private weak var store: CardStore?
    @ObservationIgnored private weak var tastings: TastingStore?
    @ObservationIgnored private weak var account: AccountStore?
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    /// Stores that can be re-pushed wholesale on Force Full Backup.
    @ObservationIgnored private var syncableStores: [any SyncableStore] = []
    /// The subset that syncs through the generic flat-record path.
    @ObservationIgnored private var remoteStores: [any RemoteSyncStore] = []

    init(outbox: SyncOutbox) {
        self.outbox = outbox
    }

    func attach(store: CardStore, account: AccountStore) {
        self.store = store
        self.account = account
        store.sink = self
        register(store)
    }

    /// Tastings written on a card by an older build, on any device, arrive
    /// with the card. They are lifted after the tastings pull, so a tombstone
    /// pulled in the same pass already blocks the import.
    func attach(tastings: TastingStore) {
        self.tastings = tastings
        tastings.sink = self
        register(tastings)
    }

    func attach(looseBrews: LooseBrewStore) {
        looseBrews.sink = self
        looseBrews.isPending = { [outbox] id in
            outbox.dirtyIDs(.looseBrew).contains(id) || outbox.tombstones(.looseBrew)[id] != nil
        }
        register(looseBrews)
    }

    private func importLegacyTastings() {
        guard let tastings, let store else { return }
        TastingMigrator.importLegacy(cards: store.cards, into: tastings)
    }

    /// Up what this phone took, down what another one did. A photo that
    /// fails stays pending and is tried on the next pass; it never blocks
    /// the tasting row, which has already synced.
    private func syncTastingPhotos(client: SupabaseClient, userID: UUID) async {
        guard let tastings else { return }
        let bucket = client.storage.from("cards")
        for tasting in tastings.tastings {
            for name in tasting.photos {
                let path = TastingPhotos.remotePath(userID: userID, tastingID: tasting.id, name: name)
                if TastingPhotos.exists(tastingID: tasting.id, name: name) {
                    guard outbox.needsUpload(tasting.id, kind: name),
                          let data = try? Data(contentsOf: TastingPhotos.url(tastingID: tasting.id, name: name)) else { continue }
                    do {
                        try await bucket.upload(path, data: data, options: FileOptions(contentType: "image/jpeg", upsert: true))
                        outbox.markImageUploaded(tasting.id, kind: name)
                    } catch {
                        Log.app.warning("tasting photo upload failed for \(tasting.id): \(error)")
                    }
                } else if let data = try? await bucket.download(path: path) {
                    TastingPhotos.write(data, tastingID: tasting.id, name: name)
                    outbox.markImageUploaded(tasting.id, kind: name)
                }
            }
        }
    }

    /// Lets a store take part in Force Full Backup and the pending counter.
    func register(_ store: any SyncableStore) {
        guard !syncableStores.contains(where: { $0 === store }) else { return }
        syncableStores.append(store)
        if let remote = store as? any RemoteSyncStore {
            remoteStores.append(remote)
        }
    }

    // MARK: - ArchiveChangeSink

    func changed(_ kind: EntityKind, id: UUID) {
        outbox.markDirty(kind, id)
        pushSoon()
    }

    func deleted(_ kind: EntityKind, id: UUID) {
        outbox.markDeleted(kind, id)
        pushSoon()
    }

    // MARK: - Lifecycle

    func start() {
        guard account?.client != nil else { return }
        outbox.purgeStaleTombstones()
        syncNow()
    }

    func pushSoon() {
        guard account?.isSignedIn == true else { return }
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            syncNow()
        }
    }

    /// Re-marks everything the app holds, for every registered store, so a full
    /// backup misses nothing regardless of what the outbox thinks it pushed.
    func forceBackup() {
        for store in syncableStores {
            for kind in store.syncKinds {
                for id in store.syncableIDs(kind) {
                    outbox.markDirty(kind, id)
                }
            }
        }

        for card in store?.cards ?? [] {
            var kinds = ["original.heic", "flat.heic", "mask.png"]
            for attachment in card.attachments {
                kinds.append("attach-\(attachment.id.uuidString).heic")
            }
            for kind in kinds {
                outbox.resetImageUpload(card.id, kind: kind)
            }
        }
        syncNow()
    }

    func syncNow() {
        guard !isSyncing else { return }
        guard let client = account?.client, account?.isSignedIn == true else { return }
        guard let userID = account?.userID else { return }

        syncTask?.cancel()
        syncTask = Task {
            isSyncing = true
            lastError = nil
            do {
                let pushGaps = try await push(client: client, userID: userID)
                try await pull(client: client, userID: userID)
                let pullGaps = try await pullEntities(client: client, userID: userID)
                importLegacyTastings()
                await syncTastingPhotos(client: client, userID: userID)
                lastSyncDate = .now
                let missing = Array(Set(pushGaps + pullGaps)).sorted()
                if let summary = outbox.errorSummary {
                    lastError = missing.isEmpty
                        ? summary
                        : [SyncSchema.message(missing: missing), summary].joined(separator: " · ")
                } else {
                    lastError = missing.isEmpty ? nil : SyncSchema.message(missing: missing)
                }
                isSyncing = false
            } catch {
                if !Task.isCancelled {
                    lastError = SyncSchema.missingRelation(in: error)
                        .map { SyncSchema.message(missing: [$0]) }
                        ?? error.localizedDescription
                    Log.app.error("sync failed: \(error)")
                }
                isSyncing = false
            }
        }
    }

    // MARK: - Push

    @discardableResult
    private func push(client: SupabaseClient, userID: UUID) async throws -> [String] {
        guard let store else { return [] }

        var missing: [String] = []

        // Dependency order: kit → water → calibrations → roasters → cards →
        // recipes (Mine) → brews. A brew that points at a recipe of yours
        // cannot land before that recipe does.
        missing += try await pushEntities(
            kinds: [.equipment, .waterProfile, .grindCalibration, .roaster],
            client: client,
            userID: userID
        )

        var cardsPendingBrews: [UUID] = []
        for cardID in outbox.dirtyIDs(.card) {
            guard let card = store.card(id: cardID) else {
                outbox.clearDirty(.card, cardID)
                continue
            }
            if outbox.shouldSkip(.card, cardID) { continue }
            try Task.checkCancellation()

            do {
                let row = CardRow(card: card, userID: userID)
                try await client.from("coffee_cards")
                    .upsert(row)
                    .execute()

                try await uploadImages(
                    cardID: card.id,
                    userID: userID,
                    client: client,
                    attachments: card.attachments
                )

                outbox.clearFailure(.card, cardID)
                cardsPendingBrews.append(cardID)
            } catch {
                if let table = SyncSchema.missingRelation(in: error) {
                    Log.app.error("sync push skipped card: missing \(table)")
                    missing.append(table)
                    continue
                }
                outbox.noteFailure(
                    .card,
                    id: cardID,
                    name: card.name.isEmpty ? "Card" : card.name,
                    message: error.localizedDescription
                )
                Log.app.error("sync push card \(cardID): \(error)")
            }
        }

        missing += try await pushEntities(
            kinds: [.recipe, .tasting, .looseBrew],
            client: client,
            userID: userID
        )

        for cardID in cardsPendingBrews {
            guard let card = store.card(id: cardID) else {
                outbox.clearDirty(.card, cardID)
                continue
            }
            let brewsOK = await pushBrews(
                of: card,
                userID: userID,
                client: client,
                missing: &missing
            )
            if brewsOK {
                outbox.clearDirty(.card, cardID)
            }
        }

        for (cardID, _) in outbox.tombstones(.card) {
            try Task.checkCancellation()
            do {
                try await client.from("coffee_cards")
                    .delete()
                    .eq("id", value: cardID)
                    .execute()

                let path = "\(userID.uuidString.lowercased())/\(cardID.uuidString.lowercased())"
                let files = try? await client.storage.from("cards").list(path: path)
                if let files, !files.isEmpty {
                    let paths = files.map { "\(path)/\($0.name)" }
                    try? await client.storage.from("cards").remove(paths: paths)
                }
                outbox.clearTombstone(.card, cardID)
            } catch {
                if let table = SyncSchema.missingRelation(in: error) {
                    missing.append(table)
                    continue
                }
                outbox.noteFailure(.card, id: cardID, name: "Deleted card", message: error.localizedDescription)
            }
        }

        if let summary = outbox.errorSummary {
            lastError = missing.isEmpty
                ? summary
                : [SyncSchema.message(missing: Array(Set(missing))), summary].joined(separator: " · ")
        }

        return missing
    }

    /// Upserts each brew of a card on its own. One bad row must not hold the
    /// rest of the archive. Returns false when something still needs retry.
    private func pushBrews(
        of card: CoffeeCard,
        userID: UUID,
        client: SupabaseClient,
        missing: inout [String]
    ) async -> Bool {
        var allOK = true
        for brew in card.brews {
            var brew = brew
            let originalID = brew.recipeID
            let originalRef = brew.recipeRef
            brew.dropOrphanRecipeLink()
            do {
                let row = BrewRow(brew: brew, cardID: card.id, userID: userID)
                try await client.from("brews")
                    .upsert(row)
                    .execute()
                if brew.recipeID != originalID || brew.recipeRef != originalRef {
                    persist(brew, on: card)
                }
                outbox.clearFailure(.card, brew.id)
            } catch {
                if let table = SyncSchema.missingRelation(in: error) {
                    missing.append(table)
                    allOK = false
                    continue
                }
                if error.localizedDescription.contains("brews_recipe_id_fkey") {
                    brew.recipeID = nil
                    do {
                        try await client.from("brews")
                            .upsert(BrewRow(brew: brew, cardID: card.id, userID: userID))
                            .execute()
                        persist(brew, on: card)
                        outbox.clearFailure(.card, brew.id)
                        continue
                    } catch {
                        Log.app.error("sync push brew \(brew.id) after dropping recipe_id: \(error)")
                    }
                }
                allOK = false
                let name = brew.recipeSnapshot?.name
                    ?? brew.method?.label
                    ?? "Brew"
                outbox.noteFailure(
                    .card,
                    id: brew.id,
                    name: "\(name) on \(card.name.isEmpty ? "card" : card.name)",
                    message: error.localizedDescription
                )
                Log.app.error("sync push brew \(brew.id): \(error)")
            }
        }

        do {
            let brewIDs = card.brews.map(\.id)
            if !brewIDs.isEmpty {
                let list = "(\(brewIDs.map(\.uuidString).joined(separator: ",")))"
                try await client.from("brews")
                    .delete()
                    .eq("card_id", value: card.id)
                    .not("id", operator: .in, value: list)
                    .execute()
            } else {
                try await client.from("brews")
                    .delete()
                    .eq("card_id", value: card.id)
                    .execute()
            }
        } catch {
            if let table = SyncSchema.missingRelation(in: error) {
                missing.append(table)
            } else {
                allOK = false
                Log.app.error("sync prune brews for \(card.id): \(error)")
            }
        }
        return allOK
    }

    private func persist(_ brew: Brew, on card: CoffeeCard) {
        guard var live = store?.card(id: card.id),
              let index = live.brews.firstIndex(where: { $0.id == brew.id }) else { return }
        guard live.brews[index].recipeID != brew.recipeID
                || live.brews[index].recipeRef != brew.recipeRef else { return }
        live.brews[index] = brew
        store?.update(live)
    }

    /// Every registered flat-record store, in one pass. Adding an entity means
    /// registering a store — no new branch here.
    private func pushEntities(
        kinds: [EntityKind]? = nil,
        client: SupabaseClient,
        userID: UUID
    ) async throws -> [String] {
        var missing: [String] = []
        let allowed = kinds.map { Set($0) }
        for store in remoteStores {
            for kind in store.syncKinds {
                if let allowed, !allowed.contains(kind) { continue }
                let dirty = outbox.dirtyIDs(kind)
                let deleted = Set(outbox.tombstones(kind).keys)
                guard !dirty.isEmpty || !deleted.isEmpty else { continue }

                try Task.checkCancellation()

                for id in dirty {
                    if outbox.shouldSkip(kind, id) { continue }
                    do {
                        try await store.pushRecords(
                            kind,
                            ids: [id],
                            deleted: [],
                            client: client,
                            userID: userID
                        )
                        outbox.clearDirty(kind, id)
                        outbox.clearFailure(kind, id)
                    } catch {
                        if let table = SyncSchema.missingRelation(in: error) {
                            Log.app.error("sync push skipped \(kind.rawValue): missing \(table)")
                            missing.append(table)
                            continue
                        }
                        outbox.noteFailure(
                            kind,
                            id: id,
                            name: kind.label,
                            message: error.localizedDescription
                        )
                        Log.app.error("sync push \(kind.rawValue) \(id): \(error)")
                    }
                }

                for id in deleted {
                    do {
                        try await store.pushRecords(
                            kind,
                            ids: [],
                            deleted: [id],
                            client: client,
                            userID: userID
                        )
                        outbox.clearTombstone(kind, id)
                    } catch {
                        if let table = SyncSchema.missingRelation(in: error) {
                            missing.append(table)
                            continue
                        }
                        outbox.noteFailure(
                            kind,
                            id: id,
                            name: "Deleted \(kind.label.lowercased())",
                            message: error.localizedDescription
                        )
                    }
                }
            }
        }
        return missing
    }

    private func pullEntities(client: SupabaseClient, userID: UUID) async throws -> [String] {
        var missing: [String] = []
        for store in remoteStores {
            for kind in store.syncKinds {
                let pullTime = Date.now
                do {
                    try Task.checkCancellation()
                    try await store.pullRecords(
                        kind,
                        since: outbox.lastPulledAt(kind),
                        client: client,
                        userID: userID
                    )
                    outbox.setLastPulledAt(pullTime, for: kind)
                } catch {
                    if error is CancellationError { throw error }
                    if let table = SyncSchema.missingRelation(in: error) {
                        Log.app.error("sync pull skipped \(kind.rawValue): missing \(table)")
                        missing.append(table)
                        continue
                    }
                    throw error
                }
            }
        }
        return missing
    }

    private func uploadImages(cardID: UUID, userID: UUID, client: SupabaseClient, attachments: [CardAttachment] = []) async throws {
        var kinds: [(CardImageKind, String)] = [
            (.original, "original.heic"),
            (.flat, "flat.heic"),
            (.mask, "mask.png"),
        ]

        for attachment in attachments {
            let filename = "attach-\(attachment.id.uuidString).heic"
            kinds.append((.attachment(attachment.id), filename))
        }

        for (kind, filename) in kinds {
            guard outbox.needsUpload(cardID, kind: filename) else { continue }
            guard ImageStore.shared.exists(cardID, kind: kind) else { continue }

            let localURL = ImageStore.shared.url(for: cardID, kind: kind)
            guard let data = try? Data(contentsOf: localURL) else { continue }

            let remotePath = "\(userID.uuidString.lowercased())/\(cardID.uuidString.lowercased())/\(filename)"
            let contentType = filename.hasSuffix(".png") ? "image/png" : "image/heic"

            try await client.storage.from("cards").upload(
                remotePath,
                data: data,
                options: FileOptions(contentType: contentType, upsert: true)
            )

            outbox.markImageUploaded(cardID, kind: filename)
        }
    }

    // MARK: - Pull

    private func pull(client: SupabaseClient, userID: UUID) async throws {
        guard let store else { return }

        var query = client.from("coffee_cards")
            .select("*, brews(*)")
            .eq("user_id", value: userID)

        if let lastPulled = outbox.lastPulledAt(.card) {
            query = query.gt("updated_at", value: lastPulled.ISO8601Format())
        }

        let pullTime = Date.now
        let response: [CardWithBrews] = try await query.execute().value

        try Task.checkCancellation()

        var cardsToInsertOrUpdate: [CoffeeCard] = []

        for remote in response {
            if outbox.tombstones(.card)[remote.row.id] != nil { continue }

            if outbox.dirtyIDs(.card).contains(remote.row.id) {
                if let local = store.card(id: remote.row.id),
                   local.updatedAt >= remote.row.updated_at {
                    continue
                }
            }

            let brews = remote.brews
                .map { $0.toBrew() }
                .sorted { $0.date > $1.date }
            cardsToInsertOrUpdate.append(remote.row.toCoffeeCard(brews: brews))
        }

        if !cardsToInsertOrUpdate.isEmpty {
            try await downloadImages(for: cardsToInsertOrUpdate, userID: userID, client: client)

            for card in cardsToInsertOrUpdate {
                if store.card(id: card.id) != nil {
                    let old = store.sink
                    store.sink = nil
                    store.update(card)
                    store.sink = old
                } else {
                    let old = store.sink
                    store.sink = nil
                    store.add(card)
                    store.sink = old
                }
            }
        }

        outbox.setLastPulledAt(pullTime, for: .card)
    }

    private func downloadImages(
        for cards: [CoffeeCard],
        userID: UUID,
        client: SupabaseClient
    ) async throws {
        for batch in cards.chunked(into: 10) {
            try Task.checkCancellation()
            await withTaskGroup(of: Void.self) { group in
                for card in batch {
                    group.addTask {
                        await self.downloadCardImages(
                            cardID: card.id,
                            userID: userID,
                            hasMask: card.hasMask,
                            attachments: card.attachments,
                            client: client
                        )
                    }
                }
            }
        }
    }

    private func downloadCardImages(
        cardID: UUID,
        userID: UUID,
        hasMask: Bool,
        attachments: [CardAttachment] = [],
        client: SupabaseClient
    ) async {
        let basePath = "\(userID.uuidString.lowercased())/\(cardID.uuidString.lowercased())"

        var filesToPull: [(CardImageKind, String, Bool)] = [
            (.original, "original.heic", true),
            (.flat, "flat.heic", true),
            (.mask, "mask.png", hasMask),
        ]

        for attachment in attachments {
            let filename = "attach-\(attachment.id.uuidString).heic"
            filesToPull.append((.attachment(attachment.id), filename, true))
        }

        for (kind, filename, shouldPull) in filesToPull {
            guard shouldPull, !ImageStore.shared.exists(cardID, kind: kind) else { continue }
            do {
                let data = try await client.storage.from("cards")
                    .download(path: "\(basePath)/\(filename)")
                try ImageStore.shared.write(data, for: cardID, kind: kind)
                outbox.markImageUploaded(cardID, kind: filename)
            } catch {
                Log.app.warning("pull \(filename) failed for \(cardID): \(error)")
            }
        }
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
