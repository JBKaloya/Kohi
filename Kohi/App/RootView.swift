import os
import SwiftUI

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = CardStore()
    @State private var isScanning = false
    /// A scan that has been filed to disk but not yet named. Presenting it is
    /// what shows the edit sheet.
    @State private var draft: CoffeeCard?

    var body: some View {
        GridScreen(onScan: { isScanning = true })
            .environment(store)
            .fullScreenCover(isPresented: $isScanning) {
                ScanScreen(
                    onScan: { scan in
                        isScanning = false
                        Task { await ingest(scan) }
                    },
                    onCancel: { isScanning = false }
                )
            }
            .sheet(item: $draft) { card in
                CardEditSheet(
                    card: card,
                    isNew: true,
                    extract: {
                        FieldParser.parse(await TextExtractor.read(cardID: card.id))
                    },
                    onSave: { saved in
                        store.markLanding(saved)
                        store.add(saved)
                    },
                    onDiscard: {
                        ImageStore.shared.removeAll(for: card.id)
                    }
                )
            }
            .task {
                await seedIfNeeded()
                #if DEBUG
                if DebugHooks.opensReview { isScanning = true }
                if DebugHooks.autoScans, let captured = DebugHooks.sampleCapture() {
                    try? await Task.sleep(for: .milliseconds(700))
                    await ingest(captured.reviewed(enhance: true))
                }
                #endif
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { store.flush() }
            }
    }

    private func ingest(_ scan: ScanResult) async {
        do {
            let card = try await Task.detached(priority: .userInitiated) {
                try await ImagePipeline.ingest(scan)
            }.value
            draft = card
        } catch {
            Log.app.error("could not file the scan: \(error)")
        }
    }

    private func seedIfNeeded() async {
        #if DEBUG
        guard SampleArchive.shouldSeed, !DebugHooks.skipsSeed else { return }
        let seeded = await Task.detached(priority: .userInitiated) {
            SampleArchive.seed()
        }.value
        for card in seeded {
            store.add(card)
        }

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
