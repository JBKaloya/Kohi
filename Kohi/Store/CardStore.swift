import Foundation
import Observation
import os

/// The single source of truth for the archive. Views read `cards`; the scan flow
/// and the edit sheet write through the mutating methods.
@Observable
final class CardStore {
    private(set) var cards: [CoffeeCard] = []

    /// Set while a freshly scanned card is flying into the grid so the tile can
    /// hold its landing animation until the transition is over.
    var landingCardID: UUID?

    @ObservationIgnored private let files: CardFileStore
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init(files: CardFileStore = CardFileStore()) {
        self.files = files
        cards = Self.sorted(files.load())
    }

    func card(id: UUID) -> CoffeeCard? {
        cards.first { $0.id == id }
    }

    func add(_ card: CoffeeCard) {
        cards = Self.sorted(cards + [card])
        ThumbnailCache.shared.warm(card)
        scheduleSave()
    }

    /// Adds many cards at once without warming every thumbnail up front, which
    /// is what the grid is for.
    func insert(_ newCards: [CoffeeCard]) {
        cards = Self.sorted(cards + newCards)
        scheduleSave()
    }

    /// Marks a card as just-arrived so its tile plays the landing animation, then
    /// clears the flag once the animation has had time to run.
    func markLanding(_ card: CoffeeCard) {
        landingCardID = card.id
        Task {
            try? await Task.sleep(for: Motion.Tile.landingWindow)
            if landingCardID == card.id { landingCardID = nil }
        }
    }

    func update(_ card: CoffeeCard) {
        guard let index = cards.firstIndex(where: { $0.id == card.id }) else { return }
        var updated = card
        updated.updatedAt = .now
        cards[index] = updated
        scheduleSave()
    }

    func delete(_ card: CoffeeCard) {
        cards.removeAll { $0.id == card.id }
        ThumbnailCache.shared.invalidate(card.id)
        let id = card.id
        Task.detached(priority: .utility) { ImageStore.shared.removeAll(for: id) }
        scheduleSave()
    }

    /// Newest scan first. The editable `date` field is for the cup, not the shelf
    /// order, so the grid stays in the order cards were collected.
    private static func sorted(_ cards: [CoffeeCard]) -> [CoffeeCard] {
        cards.sorted { $0.createdAt > $1.createdAt }
    }

    /// Coalesces a burst of edits into one write.
    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = cards
        let files = files
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await Task.detached(priority: .utility) {
                do { try files.save(snapshot) } catch { Log.app.error("save failed: \(error)") }
            }.value
            _ = self
        }
    }

    /// Writes immediately, for backgrounding.
    func flush() {
        saveTask?.cancel()
        let snapshot = cards
        try? files.save(snapshot)
    }
}
