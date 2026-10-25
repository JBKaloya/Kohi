import Foundation
import Observation

/// Regenerates stamp measurements for the archive. Owned by the root so the
/// profile sheet can show progress, and cancelled when that sheet closes.
/// One card at a time; closing the sheet stops the queue.
@MainActor
@Observable
final class StampRefresh {
    private(set) var running = false
    private(set) var completed = 0
    private(set) var total = 0
    private var task: Task<Void, Never>?

    func start(cards: [(id: UUID, roaster: String)], library: StampLibrary) {
        guard !running else { return }
        let work = cards
        running = true
        total = work.count
        completed = 0
        task = Task {
            for item in work {
                if Task.isCancelled { break }
                await InkStampPipeline.backfill(
                    cardID: item.id,
                    library: library,
                    roasterName: item.roaster,
                    force: true
                )
                if Task.isCancelled { break }
                completed += 1
            }
            running = false
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        running = false
    }
}
