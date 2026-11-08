import os
import SwiftUI

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = CardStore()
    @State private var roasters = RoasterStore()
    @State private var places = PlaceIndex()
    @State private var setup = SetupStore()
    @State private var recipes = RecipeStore()
    @State private var tastings = TastingStore()
    @State private var account = AccountStore()
    @State private var setupFlow = SetupFlowController()
    @State private var flags = AIFlags()
    @State private var lotFlags = LotFlags()
    @State private var aiEvents = AIEventLog()
    @State private var feedback = AIFeedbackStore()
    @State private var cardLooks = CardLookStore()
    @State private var stamps = StampLibrary()
    @State private var stampRefresh = StampRefresh()
    @State private var outbox = SyncOutbox()
    @State private var sync = SyncCoordinator(outbox: SyncOutbox())
    @State private var isScanning = false
    /// What the open scanner is for. Set before it opens.
    @State private var scanPurpose: ScanPurpose = .bag
    /// A café card held until the scanner finishes dismissing, then handed
    /// to the grid as `cupScan`. The same guard as `pendingScan`.
    @State private var pendingCup: CupScan?
    @State private var cupScan: CupScan?
    /// A scan that has been filed and read, but not yet named. Presenting it
    /// is what shows the edit sheet.
    @State private var draftScan: PendingScan?
    /// Holds an ingested scan until the fullScreenCover finishes dismissing,
    /// so the sheet does not race the cover animation.
    @State private var pendingScan: PendingScan?
    /// A scan that reads as a coffee already on the shelf.
    @State private var duplicate: DuplicateOffer?
    /// The new card's files, dropped when the duplicate sheet is dismissed
    /// without "This is a different coffee".
    @State private var duplicateCardID: UUID?
    @State private var duplicateKept = false
    /// A card the grid should open, after a scan recognised it.
    @State private var cardToOpen: CoffeeCard?
    @State private var isIngesting = false
    @State private var pendingVoiceNote: BrewVoiceNote.Pending?
    @State private var recoveredTranscript: String?
    @State private var showBrewDraft = false

    private var env: AppEnvironment {
        AppEnvironment(
            store: store,
            roasters: roasters,
            places: places,
            setup: setup,
            recipes: recipes,
            tastings: tastings,
            account: account,
            setupFlow: setupFlow,
            sync: sync,
            flags: flags,
            lotFlags: lotFlags,
            aiEvents: aiEvents,
            feedback: feedback,
            cardLooks: cardLooks,
            stamps: stamps,
            stampRefresh: stampRefresh
        )
    }

    var body: some View {
        GridScreen(
            onScan: { purpose in
                scanPurpose = purpose
                isScanning = true
            },
            isIngesting: isIngesting,
            openCard: $cardToOpen,
            cupScan: $cupScan
        )
            .appEnvironment(env)
            .toggleStyle(.liquid)
            .fullScreenCover(isPresented: $isScanning, onDismiss: {
                presentDraftIfReady()
                presentCupIfReady()
            }) {
                ScanScreen(
                    onScan: { scan in
                        isScanning = false
                        if case .cup(let place) = scanPurpose {
                            pendingCup = CupScan(place: place, scan: scan)
                        } else {
                            isIngesting = true
                            Task { await ingest(scan) }
                        }
                    },
                    onCancel: { isScanning = false }
                )
                .appEnvironment(env)
            }
            .onChange(of: pendingScan?.id) { _, _ in
                guard !isScanning else { return }
                presentDraftIfReady()
            }
            .sheet(item: $draftScan) { pending in
                draftSheet(pending)
            }
            .sheet(item: $duplicate, onDismiss: discardAbandonedDuplicate) { offer in
                duplicateSheet(offer)
            }
            .sheet(isPresented: $setupFlow.isPresented, onDismiss: { setupFlow.dismissed() }) {
                SetupFlowSheet(kitIsEmpty: setup.kitIsEmpty)
                    .appEnvironment(env)
            }
            .task {
                ImageStore.shared.purgeOrphanedThumbnails()
                sync = SyncCoordinator(outbox: outbox)
                sync.attach(store: store, account: account)
                roasters.sink = sync
                roasters.onReassign = { [store] old, new in
                    store.relinkRoaster(from: old, to: new)
                }
                roasters.applySeed(ReferenceBase.roasterSeeds)
                sync.register(roasters)
                setup.sink = sync
                sync.register(setup)
                recipes.sink = sync
                sync.register(recipes)
                store.tastings = tastings
                sync.attach(tastings: tastings)
                aiEvents.attach(client: SupabaseConfig.current, userID: account.userID)
                feedback.attach(client: SupabaseConfig.current, userID: account.userID)
                await flags.refresh(client: SupabaseConfig.current)
                await seedIfNeeded()
                _ = ArchiveMigrator.migrateIfNeeded(cards: store, setup: setup)
                TastingMigrator.importLegacy(cards: store.cards, into: tastings)
                BrewDiagnosis.useFlavorOrigin = lotFlags.isOn(.flavorOrigin)
                pendingVoiceNote = BrewVoiceNote.pending()
                showBrewDraft = BrewDraft.load() != nil
                sync.start()
                CardRegeneration.shared.startIfNeeded(cards: store.cards, library: stamps)
                #if DEBUG
                if DebugHooks.opensReview { isScanning = true }
                if DebugHooks.autoScans, let captured = DebugHooks.sampleCapture() {
                    try? await Task.sleep(for: .milliseconds(700))
                    await ingest(captured.reviewed(enhance: true))
                }
                #endif
            }
            .onChange(of: account.userID) { _, id in
                // Signing in gives the buffered events somewhere to go;
                // signing out takes it away again.
                aiEvents.attach(client: SupabaseConfig.current, userID: id)
                feedback.attach(client: SupabaseConfig.current, userID: id)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active {
                    store.flush()
                    roasters.flush()
                    setup.flush()
                    recipes.flush()
                    tastings.flush()
                    outbox.flush()
                    sync.pushSoon()
                }
            }
            .alert(
                Copy.resumeBrew,
                isPresented: $showBrewDraft
            ) {
                Button(Copy.resumeBrew) {
                    BrewDraft.requestResume()
                }
                Button("Discard", role: .destructive) {
                    BrewDraft.clear()
                }
            } message: {
                Text(Copy.unfinishedBrew)
            }
            .alert(
                "Unfinished recording",
                isPresented: Binding(
                    get: { pendingVoiceNote != nil && recoveredTranscript == nil },
                    set: { if !$0 { pendingVoiceNote = nil } }
                )
            ) {
                Button("Transcribe") {
                    Task { await recoverPendingVoiceNote() }
                }
                Button("Discard", role: .destructive) {
                    BrewVoiceNote.discardPending()
                    pendingVoiceNote = nil
                }
            } message: {
                Text(Copy.unfinishedVoiceNote)
            }
            .alert(
                "Brew note",
                isPresented: Binding(
                    get: { recoveredTranscript != nil },
                    set: { if !$0 { recoveredTranscript = nil } }
                )
            ) {
                Button("OK") { recoveredTranscript = nil }
            } message: {
                Text(recoveredTranscript ?? "")
            }
    }

    private func recoverPendingVoiceNote() async {
        guard let pending = pendingVoiceNote else { return }
        let note = BrewVoiceNote()
        note.attachPending(pending)
        do {
            let text = try await note.transcribe(keepAudio: lotFlags.isOn(.keepVoiceNote))
            let spoken = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !spoken.isEmpty, var card = store.cards.first(where: {
                $0.brews.contains { $0.id == pending.brewID }
            }), let index = card.brews.firstIndex(where: { $0.id == pending.brewID }) {
                var brew = card.brews[index]
                let original = brew.notes
                let parsed = SpokenBrewParser.parse(
                    spoken,
                    waters: setup.waterProfiles,
                    filters: setup.filterStock
                )
                SpokenBrewParser.apply(parsed, to: &brew)
                brew.notes = DictationTranscript.apply(spoken, to: original)
                card.brews[index] = brew
                store.update(card)
            }
            recoveredTranscript = spoken.isEmpty ? nil : spoken
        } catch {
            Log.app.notice("pending voice note: \(error)")
            recoveredTranscript = nil
        }
        pendingVoiceNote = nil
    }

    private func draftSheet(_ pending: PendingScan) -> some View {
        let visionAllowed = flags.isOn(.cardVision)
        let events = aiEvents
        return CardEditSheet(
            card: pending.card,
            isNew: true,
            // The local read already ran. What remains is the barcode, the
            // label link and, when that read is weak, vision.
            extract: {
                await ScanPipeline.fields(of: pending, visionAllowed: visionAllowed, events: events)
            },
            onSave: { saved in
                store.markLanding(saved)
                store.add(saved)
                setupFlow.noteFirstScanSaved()
                let library = stamps
                Task {
                    await InkStampPipeline.backfill(
                        cardID: saved.id,
                        library: library,
                        roasterName: saved.roaster
                    )
                }
            },
            onDiscard: {
                ImageStore.shared.removeAll(for: pending.card.id)
            }
        )
        .appEnvironment(env)
    }

    private func duplicateSheet(_ offer: DuplicateOffer) -> some View {
        DuplicateSheet(
            offer: offer,
            onOpen: { resolveDuplicate(offer) },
            onDifferent: {
                duplicateKept = true
                draftScan = offer.pending
                duplicate = nil
            },
            onAddPhoto: {
                let pending = offer.pending
                let existingID = offer.match.card.id
                duplicateKept = false
                duplicate = nil
                Task { await attachScan(pending, to: existingID) }
            }
        )
        .appEnvironment(env)
    }

    private func presentDraftIfReady() {
        guard !isScanning, let pending = pendingScan else { return }
        pendingScan = nil
        isIngesting = false
        let parsed = pending.parsed
        if let hit = CardMatch.find(
            roaster: parsed.roaster ?? "",
            name: parsed.name ?? "",
            origin: parsed,
            in: store.cards
        ) {
            duplicateKept = false
            duplicateCardID = pending.card.id
            duplicate = DuplicateOffer(pending: pending, match: hit)
        } else {
            draftScan = pending
        }
    }

    private func presentCupIfReady() {
        guard !isScanning, let cup = pendingCup else { return }
        pendingCup = nil
        scanPurpose = .bag
        cupScan = cup
    }

    /// Opens the card the scan matched. The new card's files go away with the
    /// sheet: it was never added to the archive.
    private func resolveDuplicate(_ offer: DuplicateOffer) {
        duplicateKept = false
        cardToOpen = offer.match.card
        duplicate = nil
    }

    private func discardAbandonedDuplicate() {
        if !duplicateKept, let id = duplicateCardID {
            ImageStore.shared.removeAll(for: id)
        }
        duplicateKept = false
        duplicateCardID = nil
    }

    /// Keeps the scan as another page of the card it matched.
    private func attachScan(_ pending: PendingScan, to cardID: UUID) async {
        do {
            let attachment = try await Task.detached(priority: .userInitiated) {
                try await ImagePipeline.ingestAttachment(pending.scan, cardID: cardID)
            }.value
            guard var card = store.card(id: cardID) else { return }
            card.attachments.insert(attachment, at: 0)
            store.update(card)
        } catch {
            Log.app.error("could not keep the scan as a page: \(error)")
        }
    }

    private func ingest(_ scan: ScanResult) async {
        do {
            let pending = try await Task.detached(priority: .userInitiated) {
                let card = try await ImagePipeline.ingest(scan)
                let lines = await TextExtractor.read(cardID: card.id)
                var parsed = FieldParser.parse(lines)
                parsed.linesRead = lines.count
                return PendingScan(scan: scan, card: card, lines: lines, parsed: parsed)
            }.value
            pendingScan = pending
        } catch {
            isIngesting = false
            Log.app.error("could not file the scan: \(error)")
        }
    }

    private func seedIfNeeded() async {
        #if DEBUG
        guard SampleArchive.shouldSeed, !DebugHooks.skipsSeed else { return }
        #else
        guard SampleArchive.shouldSeed else { return }
        #endif
        let savedSink = store.sink
        store.sink = nil
        defer { store.sink = savedSink }
        let seeded = await Task.detached(priority: .userInitiated) {
            SampleArchive.seed()
        }.value
        for card in seeded {
            store.add(card)
        }

        #if DEBUG
        guard let bulk = DebugHooks.bulkSeedCount, bulk > 0 else { return }
        let started = ContinuousClock.now
        let generated = await Task.detached(priority: .userInitiated) {
            DebugHooks.bulkSeed(count: bulk, from: seeded)
        }.value
        store.insert(generated)
        Log.app.notice(
            "bulk seeded \(generated.count) cards in \(started.duration(to: .now).description)"
        )
        #endif
    }
}
