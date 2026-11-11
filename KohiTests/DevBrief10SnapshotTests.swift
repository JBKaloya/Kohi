import SwiftUI
import Testing
@testable import Kohi

@Suite(.serialized)
@MainActor
struct DevBrief10SnapshotTests {
    // MARK: - Card detail

    @Test func detailOpensOnCoffee() {
        let card = Self.card(brews: 6)
        SnapshotSupport.image(
            of: Self.detail(card, startsOn: .coffee),
            height: 2_000,
            named: "detail-coffee"
        )
    }

    @Test func detailBrewsWithSixBrewsAndATasting() {
        let card = Self.card(brews: 6)
        let tastings = Self.tastingStore()
        tastings.add(Self.outTasting(cardID: card.id))
        SnapshotSupport.image(
            of: Self.detail(card, startsOn: .brews, tastings: tastings),
            height: 2_000,
            named: "detail-brews"
        )
    }

    @Test func detailBrewsBeforeAnyBrew() {
        SnapshotSupport.image(
            of: Self.detail(Self.card(brews: 0), startsOn: .brews),
            height: 1_300,
            named: "detail-brews-empty"
        )
    }

    // MARK: - Tasting flow

    @Test func flowStepWhere() {
        SnapshotSupport.image(of: Self.flow(at: .place), height: 852, named: "flow-1-where")
    }

    @Test func flowStepWhatsInTheCup() {
        SnapshotSupport.image(of: Self.flow(at: .source, draft: Self.placed()), height: 852, named: "flow-2-source")
    }

    @Test func flowStepWhichCoffee() {
        SnapshotSupport.image(of: Self.flow(at: .coffee, draft: Self.placed()), height: 852, named: "flow-3-coffee")
    }

    @Test func flowStepHowWasItMade() {
        SnapshotSupport.image(of: Self.flow(at: .made, draft: Self.named()), height: 852, named: "flow-4-made")
    }

    @Test func flowStepHowWasIt() {
        SnapshotSupport.image(of: Self.flow(at: .rating, draft: Self.named()), height: 852, named: "flow-5-rating")
    }

    @Test func flowStepHowWasItWithNotesAndIntensity() {
        var draft = Self.named()
        draft.coffee.tastingNotes = ["Jasmine", "Peach", "Black Tea"]
        draft.ratingHalves = 5
        draft.flavors = [
            FlavorTag(id: "fruity-berry-blackberry", intensity: 4),
            FlavorTag(id: "fruity-berry-raspberry"),
            FlavorTag(id: "fruity-dried-fruit-raisin", intensity: 2),
            FlavorTag(id: "floral-floral-jasmine"),
        ]
        SnapshotSupport.image(of: Self.flow(at: .rating, draft: draft), height: 1_100, named: "flow-5-rating-notes")
    }

    @Test func flowStepAnythingToRemember() {
        SnapshotSupport.image(of: Self.flow(at: .remember, draft: Self.named()), height: 1_000, named: "flow-6-remember")
    }

    @Test func flowReadingTheCard() {
        let reader = TastingReader()
        reader.isReading = true
        SnapshotSupport.image(
            of: Self.flow(at: .coffee, draft: Self.placed(), reader: reader),
            height: 852,
            named: "flow-3-reading"
        )
    }

    @Test func flowAfterTheReadWithAGuessToConfirm() {
        let reader = TastingReader()
        reader.uncertain = [MenuField(kind: .roaster, value: "Belleville", confidence: .uncertain)]
        var draft = Self.named()
        draft.coffee.name = "Kenya Tekangu"
        draft.coffee.country = "Kenya"
        draft.coffee.process = "Washed"
        SnapshotSupport.image(
            of: Self.flow(at: .coffee, draft: draft, reader: reader),
            height: 1_100,
            named: "flow-3-read"
        )
    }

    // MARK: - Scan question

    @Test func scanIntentSheet() {
        SnapshotSupport.image(
            of: ScanIntentSheet(
                suggestion: PlaceSuggestion(place: Self.galata, placeID: "galata", source: .seed),
                onAnswer: { _ in }
            ),
            height: ScanIntentSheet.height,
            named: "scan-intent"
        )
    }

    // MARK: - Fixtures

    private static let galata = Place(
        name: "Galata Bakery & Coffee",
        address: "13 Rue Saint-Augustin",
        latitude: 48.8689,
        longitude: 2.3376,
        city: "Paris"
    )

    private static let crible = SeedPlace(
        id: "crible",
        name: "Crible",
        brand: "Crible",
        address: "75 Rue Buffon, 75005",
        postalCode: "75005",
        arrondissement: 5,
        city: "Paris",
        roasterIDs: ["feve"],
        status: .open,
        closedOn: nil,
        fetchedAt: "2026-10-01"
    )

    private static func placed() -> TastingDraft {
        var draft = TastingDraft()
        draft.date = Date(timeIntervalSince1970: 1_790_000_000)
        draft.choose(galata, "galata")
        return draft
    }

    private static func named() -> TastingDraft {
        var draft = placed()
        draft.coffee.name = "Chelbesa"
        draft.coffee.roaster = "Fève"
        return draft
    }

    private static func card(brews: Int) -> CoffeeCard {
        var card = CoffeeCard(
            id: UUID(uuidString: "6B1E0C2A-0000-4000-8000-0000000000A0")!,
            name: "Chelbesa",
            roaster: "Fève",
            country: "Ethiopia"
        )
        card.process = "Washed"
        card.tastingNotes = ["Jasmine", "Peach"]
        card.createdAt = Date(timeIntervalSince1970: 1_789_000_000)
        card.date = card.createdAt
        card.brews = (0..<brews).map { index in
            Brew(
                date: Date(timeIntervalSince1970: 1_790_000_000 - Double(index) * 86_400),
                method: .v60,
                dose: 15,
                water: 250,
                seconds: 180 + index * 5,
                rating: 3 + index % 3
            )
        }
        return card
    }

    private static func outTasting(cardID: UUID) -> Tasting {
        Tasting(
            id: UUID(uuidString: "6B1E0C2A-0000-4000-8000-0000000000B0")!,
            date: Date(timeIntervalSince1970: 1_790_000_000),
            context: .out(place: galata, placeID: "galata"),
            cardID: cardID,
            coffee: TastedCoffee(name: "Chelbesa", roaster: "Fève", country: "Ethiopia"),
            rating: 4,
            note: "At the bar"
        )
    }

    private static func tastingStore() -> TastingStore {
        let name = UUID().uuidString
        return TastingStore(
            files: JSONFileStore(filename: "tastings-shot10-\(name).json"),
            ledgerFile: JSONDocumentStore(filename: "tastings-ledger-shot10-\(name).json")
        )
    }

    private static func flow(at step: TastingStep, draft: TastingDraft? = nil, reader: TastingReader? = nil) -> some View {
        world().apply(
            TastingFlow(
                previewSuggestions: [crible],
                requestsLocation: false,
                startsAt: step,
                draft: draft,
                reader: reader
            )
        )
    }

    private static func detail(_ card: CoffeeCard, startsOn tab: CardDetailTab, tastings: TastingStore? = nil) -> some View {
        let world = world(tastings: tastings)
        world.store.add(card)
        return world.apply(NavigationStack { CardDetailView(card: card, startsOn: tab) })
    }

    private static func world(tastings: TastingStore? = nil) -> AppEnvironment {
        let name = UUID().uuidString
        let defaults = UserDefaults(suiteName: "kohi-shot10-\(name)")!
        return AppEnvironment(
            store: CardStore(files: CardFileStore(url: URL(fileURLWithPath: "/tmp/kohi-shot10-cards-\(name).json"))),
            roasters: RoasterStore(
                files: JSONFileStore(filename: "roasters-shot10-\(name).json"),
                seedStamp: JSONDocumentStore(filename: "roaster-stamp-shot10-\(name).json")
            ),
            places: PlaceIndex(places: [], notes: JSONDocumentStore(filename: "place-notes-shot10-\(name).json")),
            setup: SetupStore(files: JSONDocumentStore(filename: "setup-shot10-\(name).json")),
            recipes: RecipeStore(files: JSONFileStore(filename: "recipes-shot10-\(name).json")),
            tastings: tastings ?? tastingStore(),
            looseBrews: LooseBrewStore(
                files: JSONFileStore(filename: "loose-brews-shot10-\(name).json"),
                ledgerFile: JSONDocumentStore(filename: "loose-brews-ledger-shot10-\(name).json")
            ),
            account: AccountStore(),
            setupFlow: SetupFlowController(),
            sync: SyncCoordinator(outbox: SyncOutbox()),
            flags: AIFlags(defaults: defaults),
            lotFlags: LotFlags(defaults: defaults),
            aiEvents: AIEventLog(),
            feedback: AIFeedbackStore(files: JSONFileStore(filename: "feedback-shot10-\(name).json")),
            cardLooks: CardLookStore(defaults: defaults),
            stamps: StampLibrary(),
            stampRefresh: StampRefresh()
        )
    }
}

private extension AppEnvironment {
    func apply<V: View>(_ view: V) -> some View {
        view.appEnvironment(self)
    }
}
