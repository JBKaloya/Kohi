import Foundation
import Testing
@testable import Kohi

/// A photographed menu, read on device.
struct MenuParserTests {
    private let roasters = ["Fève", "Belleville", "Coutume"]

    @Test func oneCoffeeOnAChalkboard() {
        let lines = [
            "MENU",
            "Ethiopia Guji 5,50 €",
            "Fève",
            "Washed",
            "Notes: jasmine, peach",
        ]
        let candidates = MenuParser.parse(lines, roasters: roasters)
        #expect(candidates.count == 1)
        let coffee = candidates[0]
        #expect(coffee.name == "Ethiopia Guji")
        #expect(coffee.field(.name)?.confidence == .read)
        #expect(coffee.field(.country)?.value == "Ethiopia")
        #expect(coffee.field(.roaster)?.value == "Fève")
        #expect(coffee.field(.roaster)?.confidence == .read)
        #expect(coffee.field(.process)?.value == "Washed")
        #expect(coffee.field(.notes)?.value == "jasmine, peach")
        #expect(coffee.field(.price)?.confidence == .read)
        #expect(coffee.field(.variety) == nil)
    }

    @Test func aBoardOfSeveralCoffeesSplitsOnEachTitle() {
        let lines = [
            "FILTRE",
            "Kenya Kiambu AA",
            "Belleville",
            "6 €",
            "Colombia El Paraiso",
            "Natural",
            "7 €",
        ]
        let candidates = MenuParser.parse(lines, roasters: roasters)
        #expect(candidates.map(\.name) == ["Kenya Kiambu AA", "Colombia El Paraiso"])
        // A section header is a guess about the method, never a read.
        #expect(candidates[0].field(.method)?.value == "Batch")
        #expect(candidates[0].field(.method)?.confidence == .uncertain)
        #expect(candidates[1].field(.process)?.value == "Natural")
    }

    @Test func aRoasterInsideALongerLineIsUncertain() {
        let lines = ["Panama Gesha roasted with love at Coutume Paris"]
        let coffee = MenuParser.parse(lines, roasters: roasters).first
        #expect(coffee?.field(.roaster)?.value == "Coutume")
        #expect(coffee?.field(.roaster)?.confidence == .uncertain)
        #expect(coffee?.field(.name)?.confidence == .uncertain)
    }

    @Test func aMenuWithoutCoffeesOffersNothing() {
        #expect(MenuParser.parse(["MENU", "Coffee", "Today"]).isEmpty)
    }

    @Test func theModelIsKeptOnlyWhereTheMenuSaysSo() {
        let lines = ["Ethiopia Guji 5,50 €", "Fève"]
        let model = [MenuCandidate(id: 0, fields: [
            MenuField(kind: .name, value: "Ethiopia Guji", confidence: .read),
            MenuField(kind: .roaster, value: "Fève", confidence: .read),
            MenuField(kind: .variety, value: "Heirloom", confidence: .read),
            MenuField(kind: .price, value: "€5.50", confidence: .read),
        ])]
        let grounded = MenuParser.grounded(model, in: lines)
        #expect(grounded[0].field(.name)?.confidence == .read)
        #expect(grounded[0].field(.roaster)?.confidence == .read)
        #expect(grounded[0].field(.variety)?.confidence == .uncertain)
        #expect(grounded[0].field(.price)?.confidence == .read)
    }
}

/// The suggestions under the coffee name.
@MainActor
struct CoffeeSuggestionsTests {
    private let crible = Place(name: "Crible", address: "75 Rue Buffon", latitude: 48.84, longitude: 2.35)

    @Test func eachRowSaysWhereItComesFrom() {
        let card = CoffeeCard(name: "Chelbesa", roaster: "Fève", country: "Ethiopia")
        let tasted = Tasting(
            context: .out(place: crible, placeID: "crible"),
            coffee: TastedCoffee(name: "Chelbesa Natural", roaster: "Dak")
        )
        let rows = CoffeeSuggestions.suggest("chelbesa", cards: [card], tastings: [tasted], roasters: ["Fève"])
        #expect(rows.first?.source == .collection(cardID: card.id))
        #expect(rows.first?.match == .exact)
        #expect(rows.first?.label == Copy.inCoffeeCollection)
        let before = rows.first { $0.source == .tastedBefore }
        #expect(before?.match == .approximate)
        #expect(before?.label == "\(Copy.tastedBefore) · close match")
    }

    @Test func aRoasterIsOfferedButNeverMerged() {
        let rows = CoffeeSuggestions.suggest("fev", cards: [], tastings: [], roasters: ["Fève", "Fève"])
        #expect(rows.count == 1)
        #expect(rows.first?.source == .roaster)
    }

    @Test func oneLetterSuggestsNothing() {
        #expect(CoffeeSuggestions.suggest("c", cards: [CoffeeCard(name: "Chelbesa")], tastings: [], roasters: []).isEmpty)
    }
}

/// The compose form's rules, without the view.
struct TastingDraftTests {
    private let crible = Place(name: "Crible", address: "75 Rue Buffon", latitude: 48.84, longitude: 2.35)

    @Test func saveNeedsANameAndAPlace() {
        var draft = TastingDraft()
        #expect(!draft.canSave)
        draft.coffee.name = "Gesha"
        #expect(!draft.canSave)
        draft.choose(crible, "crible")
        #expect(draft.canSave)
        draft.coffee.name = "   "
        #expect(!draft.canSave)
    }

    @Test func methodChipsMapOntoTheBrewVocabulary() {
        var draft = TastingDraft()
        draft.coffee.name = "Gesha"
        draft.choose(crible, nil)
        draft.method = .v60
        var tasting = draft.tasting(base: nil)
        #expect(tasting.method == .filter && tasting.brewer == .v60 && !tasting.isBatch)
        draft.method = .batch
        tasting = draft.tasting(base: nil)
        #expect(tasting.method == .filter && tasting.isBatch)
        draft.method = .other
        draft.methodNote = "Siphon"
        tasting = draft.tasting(base: nil)
        #expect(tasting.method == nil && tasting.methodNote == "Siphon")
        #expect(TastingMethod(method: tasting.method, brewer: tasting.brewer, isBatch: tasting.isBatch, note: tasting.methodNote) == .other)
    }

    @Test func aPriceKeepsItsCommaAndCurrency() {
        var draft = TastingDraft()
        draft.priceText = "5,50"
        draft.currency = "EUR"
        #expect(draft.price == CupPrice(amount: Decimal(string: "5.5")!, currency: "EUR"))
        draft.priceText = "0"
        #expect(draft.price == nil)
    }

    @Test func linkingACardCopiesItOnceAndABagNeverOverwrites() {
        var card = CoffeeCard(name: "Chelbesa", roaster: "Fève", country: "Ethiopia")
        var draft = TastingDraft()
        draft.link(card)
        #expect(draft.cardID == card.id)
        #expect(draft.coffee.name == "Chelbesa")
        card.name = "Renamed later"
        #expect(draft.coffee.name == "Chelbesa")

        var parsed = ParsedFields()
        parsed.name = "Something else"
        parsed.variety = "Heirloom"
        draft.fill(from: parsed)
        #expect(draft.coffee.name == "Chelbesa")
        #expect(draft.coffee.variety == "Heirloom")
    }

    @Test func editingKeepsIdentityAndCreation() {
        let original = Tasting(
            context: .out(place: crible, placeID: "crible"),
            coffee: TastedCoffee(name: "Gesha"),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        var draft = TastingDraft(original)
        draft.note = "better the second time"
        let edited = draft.tasting(base: original)
        #expect(edited.id == original.id)
        #expect(edited.createdAt == original.createdAt)
        #expect(edited.note == "better the second time")
        #expect(edited.place == crible)
    }
}
