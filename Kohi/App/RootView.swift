import os
import SwiftUI

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = CardStore()
    @State private var roasters = RoasterStore()
    @State private var setup = SetupStore()
    @State private var recipes = RecipeStore()
    @State private var account = AccountStore()
    @State private var setupFlow = SetupFlowController()
    @State private var flags = AIFlags()
    @State private var lotFlags = LotFlags()
    @State private var aiEvents = AIEventLog()
    @State private var feedback = AIFeedbackStore()
    @State private var outbox = SyncOutbox()
    @State private var sync = SyncCoordinator(outbox: SyncOutbox())
    @State private var isScanning = false
    /// A scan that has been filed to disk but not yet named. Presenting it is
    /// what shows the edit sheet.
    @State private var draft: CoffeeCard?
    /// Holds an ingested card until the fullScreenCover finishes dismissing,
    /// so the sheet does not race the cover animation.
    @State private var pendingScan: CoffeeCard?
    @State private var isIngesting = false

    private var env: AppEnvironment {
        AppEnvironment(
            store: store,
            roasters: roasters,
            setup: setup,
            recipes: recipes,
            account: account,
            setupFlow: setupFlow,
            sync: sync,
            flags: flags,
            lotFlags: lotFlags,
            aiEvents: aiEvents,
            feedback: feedback
        )
    }

    var body: some View {
        GridScreen(onScan: { isScanning = true }, isIngesting: isIngesting)
            .appEnvironment(env)
            .fullScreenCover(isPresented: $isScanning, onDismiss: {
                presentDraftIfReady()
            }) {
                ScanScreen(
                    onScan: { scan in
                        isScanning = false
                        isIngesting = true
                        Task { await ingest(scan) }
                    },
                    onCancel: { isScanning = false }
                )
                .appEnvironment(env)
            }
            .onChange(of: pendingScan) { _, _ in
                guard !isScanning else { return }
                presentDraftIfReady()
            }
            .sheet(item: $draft) { card in
                CardEditSheet(
                    card: card,
                    isNew: true,
                    // Vision and the link fetch are detached because
                    // `SWIFT_APPROACHABLE_CONCURRENCY` makes a nonisolated async
                    // call run on the caller's actor: awaited straight from the
                    // sheet's `task`, all of this would run on the main thread
                    // and freeze the form until the read finished.
                    extract: { [visionAllowed = flags.isOn(.cardVision)] in
                        await Task.detached(priority: .userInitiated) {
                            async let ocrLines = TextExtractor.read(cardID: card.id)
                            async let codePayload = LabelCodeReader.read(cardID: card.id)

                            let lines = await ocrLines
                            var parsed = FieldParser.parse(lines)
                            parsed.linesRead = lines.count

                            let code = await codePayload
                            if let code, code.hasPrefix("http") {
                                if parsed.productURL == nil {
                                    parsed.productURL = code
                                }
                            } else {
                                parsed.labelCode = code
                            }

                            if let code, code.hasPrefix("http"),
                               let linked = await LabelLink.fetch(code) {
                                parsed.mergeLinked(linked)
                            }

                            // Weak local read — handwriting, CJK, free-form
                            // layout — gets a second opinion from the vision
                            // model, which only ever fills what is still empty.
                            if parsed.wantsVisionAssist, visionAllowed, CardVision.isAvailable,
                               let vision = await CardVision.read(cardID: card.id) {
                                parsed.fillMissing(from: vision)
                            }

                            return parsed
                        }.value
                    },
                    onSave: { saved in
                        store.markLanding(saved)
                        store.add(saved)
                        setupFlow.noteFirstScanSaved()
                        if saved.poster == .pending {
                            generatePoster(for: saved)
                        }
                    },
                    onDiscard: {
                        ImageStore.shared.removeAll(for: card.id)
                    }
                )
                .appEnvironment(env)
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
                sync.register(roasters)
                setup.sink = sync
                sync.register(setup)
                recipes.sink = sync
                sync.register(recipes)
                aiEvents.attach(client: SupabaseConfig.current, userID: account.userID)
                feedback.attach(client: SupabaseConfig.current, userID: account.userID)
                await flags.refresh(client: SupabaseConfig.current)
                await seedIfNeeded()
                _ = ArchiveMigrator.migrateIfNeeded(cards: store, setup: setup)
                BrewDiagnosis.useFlavorOrigin = lotFlags.isOn(.flavorOrigin)
                sync.start()
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
                    outbox.flush()
                    sync.pushSoon()
                }
            }
    }

    private func presentDraftIfReady() {
        guard let card = pendingScan else { return }
        draft = card
        pendingScan = nil
        isIngesting = false
    }

    private func ingest(_ scan: ScanResult) async {
        do {
            let card = try await Task.detached(priority: .userInitiated) {
                try await ImagePipeline.ingest(scan)
            }.value
            pendingScan = card
        } catch {
            isIngesting = false
            Log.app.error("could not file the scan: \(error)")
        }
    }

    private func generatePoster(for card: CoffeeCard) {
        guard flags.isOn(.poster), CardPoster.isAvailable else {
            print("[card-poster] generatePoster skipped: isAvailable == false")
            return
        }
        let cardID = card.id
        var pending = card
        pending.poster = .pending
        store.update(pending)
        print("[card-poster] generatePoster: set pending for \(cardID)")
        Task {
            let success = await Task.detached(priority: .utility) {
                await CardPoster.generate(cardID: cardID)
            }.value
            print("[card-poster] generatePoster: generate returned \(success)")
            guard var latest = store.card(id: cardID) else {
                print("[card-poster] generatePoster: card not found in store!")
                return
            }
            latest.poster = success ? .ready : .failed
            store.update(latest)
            print("[card-poster] generatePoster: store updated → \(latest.poster)")
            if success {
                ThumbnailCache.shared.warm(latest, buckets: ThumbnailCache.buckets)
            }
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
