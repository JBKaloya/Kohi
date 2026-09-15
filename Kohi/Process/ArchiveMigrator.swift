import Foundation
import os

/// Second-stage migration: needs Setup (for the single-grinder heuristic)
/// and the flavor wheel. Decode already lifted grind strings and 1…5 taste.
/// This pass writes once and remembers, so deleting a grinder later does
/// not put it back.
nonisolated enum ArchiveMigrator {
    struct Report: Equatable, Sendable {
        var brews: Int = 0
        var grindValues: Int = 0
        var grindRawOnly: Int = 0
        var grindersGuessed: Int = 0
        var axesConverted: Int = 0
        var unmatchedNotes: [String] = []
    }

    private static let doneKey = "lot2.archiveMigrated"

    static var hasRun: Bool {
        UserDefaults.standard.bool(forKey: doneKey)
    }

    @MainActor
    static func migrateIfNeeded(cards: CardStore, setup: SetupStore) -> Report {
        var guessed = 0
        if !hasRun {
            let onlyGrinder = setup.grinders.count == 1 ? setup.grinders.first : nil
            for card in cards.cards {
                var next = card
                var cardChanged = false
                for index in next.brews.indices {
                    var brew = next.brews[index]
                    if brew.grind.grinderId == nil, let onlyGrinder, !brew.grind.isEmpty {
                        brew.grind.grinderId = onlyGrinder.id
                        guessed += 1
                        cardChanged = true
                    }
                    if !brew.flavors.isEmpty {
                        let rematched = FlavorMatcher.match(brew.flavors.map(\.displayName))
                        if rematched.tags != brew.flavors {
                            brew.flavors = rematched.tags
                            cardChanged = true
                        }
                    }
                    if cardChanged { next.brews[index] = brew }
                }
                if cardChanged {
                    cards.update(next)
                }
            }
            UserDefaults.standard.set(true, forKey: doneKey)
        }

        var report = inspect(cards: cards.cards, grinders: setup.grinders)
        report.grindersGuessed = guessed
        #if DEBUG
        if ProcessInfo.processInfo.environment["KOHI_MIGRATION_REPORT"] != nil {
            Log.app.notice(
                """
                lot2 migration: \(report.brews) brews, \
                \(report.grindValues) grind values, \
                \(report.grindRawOnly) raw-only, \
                \(report.grindersGuessed) grinders guessed, \
                \(report.axesConverted) axes converted, \
                unmatched: \(report.unmatchedNotes.joined(separator: ", "))
                """
            )
        }
        #endif
        return report
    }

    static func inspect(cards: [CoffeeCard], grinders: [Equipment]) -> Report {
        var report = Report()
        for card in cards {
            for brew in card.brews + [card.recipeSuggestion].compactMap(\.self) {
                report.brews += 1
                if brew.grind.value != nil { report.grindValues += 1 }
                else if !brew.grind.isEmpty { report.grindRawOnly += 1 }
                report.axesConverted += brew.legacyTaste?.count ?? 0
                let match = FlavorMatcher.match(card.tastingNotes)
                report.unmatchedNotes.append(contentsOf: match.unmatched)
            }
        }
        report.unmatchedNotes = Array(Set(report.unmatchedNotes)).sorted()
        return report
    }
}
