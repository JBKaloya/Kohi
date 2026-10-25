import Foundation
import os

/// Lifts the coffee-shop tastings that used to live on cards into the
/// standalone store.
///
/// The card array is never touched: older builds keep reading it, and a
/// rollback loses nothing. Each import keeps its id, so two devices importing
/// the same tasting converge on one row, and the ledger makes the import a
/// one-time event per id, deletes included.
nonisolated enum TastingMigrator {
    /// The tastings on these cards that the ledger has never seen.
    /// Legacy `.home` entries stay where they are.
    static func candidates(cards: [CoffeeCard], known: (UUID) -> Bool) -> [Tasting] {
        var seen = Set<UUID>()
        var result: [Tasting] = []
        for card in cards {
            for legacy in card.tastings {
                guard case .out = legacy.context else { continue }
                guard !known(legacy.id), seen.insert(legacy.id).inserted else { continue }
                result.append(standalone(legacy, from: card))
            }
        }
        return result
    }

    /// The same cup, now carrying its coffee. `updatedAt` stays at the date it
    /// was drunk so any row already on the server is newer.
    static func standalone(_ legacy: Tasting, from card: CoffeeCard) -> Tasting {
        var tasting = legacy
        tasting.cardID = card.id
        if tasting.coffee.trimmedName.isEmpty {
            tasting.coffee = TastedCoffee(card: card)
        }
        tasting.createdAt = legacy.date
        tasting.updatedAt = legacy.date
        tasting.deletedAt = nil
        return tasting
    }

    @MainActor
    @discardableResult
    static func importLegacy(cards: [CoffeeCard], into store: TastingStore) -> Int {
        let found = candidates(cards: cards, known: store.knows)
        let count = store.importLegacy(found)
        if count > 0 {
            Log.app.info("imported \(count) legacy tastings")
        }
        return count
    }
}
