import Foundation
import Testing
@testable import Kohi

/// A brew started without a coffee (11 November): it saves, waits in the
/// log, and moves onto a card once one is linked.
@MainActor
struct LooseBrewTests {
    private func journey() -> (session: BrewSession, loose: LooseBrewStore, cards: CardStore, setup: SetupStore) {
        let setup = BrewJourneySupport.setup()
        let loose = BrewJourneySupport.looseBrews()
        let session = BrewSession.withoutCoffee(store: loose, setup: setup)
        return (session, loose, BrewJourneySupport.cards(), setup)
    }

    @Test func aRowWithoutACardSurvivesTheRoundTrip() {
        var brew = Brew(method: .v60, dose: 15, water: 250, notes: "Geisha, other app")
        brew.coffee = TastedCoffee(name: "Geisha", roaster: "Hydrangea")
        let row = BrewRow(brew: brew, cardID: nil, userID: UUID())

        let restored = row.toBrew()

        #expect(row.card_id == nil)
        #expect(restored.id == brew.id)
        #expect(restored.coffee == brew.coffee)
        #expect(restored.notes == brew.notes)
    }

    @Test func aCardsBrewNeverCarriesTheCoffeeColumn() throws {
        var brew = Brew(method: .v60, dose: 15, water: 250)
        brew.coffee = TastedCoffee(name: "Stale")
        let row = BrewRow(brew: brew, cardID: UUID(), userID: UUID())
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(row)) as? [String: Any]

        #expect(json?["coffee"] == nil)
        #expect(row.toBrew().coffee == nil)
    }

    @Test func theJourneyKeepsItsOrderWithoutACoffee() {
        let setup = BrewJourneySupport.setup()
        let picked = BrewSession(card: BrewJourneySupport.card(agitation: nil), fromCard: false, setup: setup)
        let (skipped, _, _, _) = journey()

        #expect(!skipped.hasCard)
        #expect(skipped.step == .scope)
        #expect(skipped.progressTotal == picked.progressTotal)
        #expect(skipped.progressIndex == picked.progressIndex)
    }

    @Test func savingWithoutACoffeeGoesToTheLooseStoreOnly() {
        let (session, loose, cards, setup) = journey()
        session.alreadyBrewed(in: setup)
        session.brew.dose = 16
        session.finish(store: cards, events: AIEventLog())

        #expect(loose.brews.map(\.id) == [session.brew.id])
        #expect(loose.brews.first?.coffee != nil)
        #expect(cards.cards.isEmpty)
    }

    @Test func linkingMovesTheSavedBrewOntoTheCard() {
        let (session, loose, cards, setup) = journey()
        session.alreadyBrewed(in: setup)
        session.brew.coffee = TastedCoffee(name: "Geisha")
        session.finish(store: cards, events: AIEventLog())
        let card = BrewJourneySupport.card(agitation: nil)
        cards.add(card)

        #expect(loose.link(session.brew.id, to: card.id, in: cards))

        #expect(loose.isEmpty)
        let linked = cards.card(id: card.id)?.brews.first { $0.id == session.brew.id }
        #expect(linked != nil)
        #expect(linked?.coffee == nil)
    }

    @Test func linkingDuringTheJourneySavesOnTheCard() {
        let (session, loose, cards, setup) = journey()
        let card = BrewJourneySupport.card(agitation: nil)
        cards.add(card)
        session.alreadyBrewed(in: setup)
        session.link(to: card, store: cards)
        session.finish(store: cards, events: AIEventLog())

        #expect(session.hasCard)
        #expect(loose.isEmpty)
        #expect(cards.card(id: card.id)?.brews.contains { $0.id == session.brew.id } == true)
    }

    @Test func anUnlinkedBrewStaysInTheLogAndOutOfTheGrid() {
        let (session, loose, cards, setup) = journey()
        session.alreadyBrewed(in: setup)
        session.finish(store: cards, events: AIEventLog())
        let rows = BrewArchive.recent(in: cards.cards, loose: loose.brews)

        #expect(rows.count == 1)
        #expect(rows.first?.card == nil)
        #expect(cards.cards.isEmpty)
    }

    @Test func aPullOnlyDropsWhatTheServerConfirmedGone() {
        let loose = BrewJourneySupport.looseBrews()
        let offline = Brew(method: .v60, coffee: TastedCoffee())
        let synced = Brew(method: .v60, coffee: TastedCoffee())
        let linkedElsewhere = Brew(method: .v60, coffee: TastedCoffee())
        loose.save(offline)
        loose.merge([synced, linkedElsewhere])

        loose.reconcile(linked: [linkedElsewhere.id], present: [linkedElsewhere.id])

        #expect(Set(loose.brews.map(\.id)) == [offline.id])
    }

    @Test func aRecipeSavedFromALooseBrewPointsAtNoCard() throws {
        let source = try String(
            contentsOf: BrewJourneySupport.kohiRoot().appending(path: "Recipes/AfterBrewSheet.swift"),
            encoding: .utf8
        )
        #expect(source.contains("if !session.hasCard {\n                        saved.cardID = nil"))
    }

    @Test func aDraftWithoutACoffeeResumesWithoutOne() {
        let (session, loose, cards, setup) = journey()
        BrewDraft.save(session)
        defer { BrewDraft.clear() }
        let payload = BrewDraft.load()

        #expect(payload?.loose == true)
        let resumed = payload.flatMap {
            BrewDraft.session(
                from: $0,
                store: cards,
                recipes: RecipeStore(files: JSONFileStore(filename: "recipes-loose-\(UUID().uuidString).json")),
                looseBrews: loose,
                setup: setup
            )
        }
        #expect(resumed?.hasCard == false)
    }
}
