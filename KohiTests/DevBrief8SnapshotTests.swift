import SwiftUI
import Testing
@testable import Kohi

@Suite(.serialized)
@MainActor
struct DevBrief8SnapshotTests {
    @Test func duplicateSheetForAStrongMatch() {
        SnapshotSupport.image(
            of: DuplicateSheet(
                offer: Self.offer(confidence: .strong),
                onOpen: {},
                onDifferent: {},
                onAddPhoto: {}
            ),
            height: 520,
            named: "duplicate-strong"
        )
    }

    @Test func duplicateSheetForAProbableMatch() {
        SnapshotSupport.image(
            of: DuplicateSheet(
                offer: Self.offer(confidence: .probable),
                onOpen: {},
                onDifferent: {},
                onAddPhoto: {}
            ),
            height: 520,
            named: "duplicate-probable"
        )
    }

    @Test func whereSheetWithAFix() {
        SnapshotSupport.image(
            of: Self.hosted(
                WhereSheet(
                    roaster: "Fève",
                    nearby: NearbyPlaces(),
                    previewSuggestions: [Self.crible, Self.temp],
                    requestsLocation: false,
                    onPick: { _, _ in }
                )
            ),
            height: 520,
            named: "where-fix"
        )
    }

    @Test func whereSheetWithoutAFix() {
        SnapshotSupport.image(
            of: Self.hosted(
                WhereSheet(
                    roaster: "Fève",
                    nearby: NearbyPlaces(),
                    previewSuggestions: [],
                    requestsLocation: false,
                    onPick: { _, _ in }
                )
            ),
            height: 420,
            named: "where-none"
        )
    }

    @Test func composeSheetBeforeAnythingIsTyped() {
        SnapshotSupport.image(
            of: Self.hosted(TastingComposeSheet(previewSuggestions: [Self.crible], requestsLocation: false)),
            height: 1_400,
            named: "compose-empty"
        )
    }

    @Test func composeSheetEditingAFullTasting() {
        SnapshotSupport.image(
            of: Self.hosted(TastingComposeSheet(editing: Self.outTasting, previewSuggestions: [], requestsLocation: false)),
            height: 2_400,
            named: "compose-edit"
        )
    }

    @Test func tastingDetailReadsCoffeeVisitAndCup() {
        let store = Self.tastingStore()
        store.add(Self.outTasting)
        SnapshotSupport.image(
            of: Self.hosted(NavigationStack {
                TastingDetailView(tastingID: Self.outTasting.id)
            }, tastings: store),
            height: 900,
            named: "detail"
        )
    }

    @Test func tastingsTabEmptyState() {
        SnapshotSupport.image(
            of: Self.hosted(TastingsScreen(onAdd: {}, opened: .constant(nil), openedPlace: .constant(nil))),
            height: 500,
            named: "tab-empty"
        )
    }

    @Test func tastingsSectionWithBothGroups() {
        let card = CoffeeCard(
            name: "Chelbesa",
            roaster: "Fève",
            brews: [Brew(method: .v60, dose: 15, water: 250, rating: 5)]
        )
        let tasted = [
            Tasting(
                context: .out(
                    place: Place(name: "Crible", address: "75 Rue Buffon", latitude: 0, longitude: 0),
                    placeID: "crible"
                ),
                rating: 4,
                taste: TasteProfile(acidity: 8, sweetness: 5, body: 3),
                flavors: [FlavorTag(custom: "Jasmine"), FlavorTag(custom: "Peach")],
                acidity: 1,
                note: "at the bar"
            )
        ]
        SnapshotSupport.image(
            of: Self.section(card, tasted: tasted).padding(26),
            height: 460,
            named: "both"
        )
    }

    @Test func tastingsSectionWithOnlyHome() {
        let card = CoffeeCard(
            name: "Chelbesa",
            brews: [Brew(method: .v60, dose: 15, water: 250, rating: 5)]
        )
        SnapshotSupport.image(
            of: Self.section(card).padding(26),
            height: 320,
            named: "home"
        )
    }

    @Test func tastingsSectionWithNothingLogged() {
        SnapshotSupport.image(
            of: Self.section(CoffeeCard(name: "Chelbesa")).padding(26),
            height: 120,
            named: "none"
        )
    }

    private static func section(_ card: CoffeeCard, tasted: [Tasting] = []) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            BrewsSection(card: card, onSelectBrew: { _ in })
            TastedAtSection(tasted: tasted, onOpenTasting: { _ in })
        }
    }

    private static let outTasting = Tasting(
        id: UUID(uuidString: "6B1E0C2A-0000-4000-8000-000000000001")!,
        date: Date(timeIntervalSince1970: 1_790_000_000),
        context: .out(
            place: Place(name: "Crible", address: "75 Rue Buffon", latitude: 48.84, longitude: 2.36, city: "Paris"),
            placeID: "crible"
        ),
        coffee: TastedCoffee(name: "Chelbesa", roaster: "Fève", country: "Ethiopia", process: "Washed", tastingNotes: ["Jasmine", "Peach"]),
        method: .filter,
        brewer: .v60,
        price: CupPrice(amount: 5.5, currency: "EUR"),
        rating: 4,
        taste: TasteProfile(acidity: 8, sweetness: 5, body: 3),
        flavors: [FlavorTag(custom: "Jasmine"), FlavorTag(custom: "Peach")],
        note: "Bright, at the bar"
    )

    private static func tastingStore() -> TastingStore {
        let name = UUID().uuidString
        return TastingStore(
            files: JSONFileStore(filename: "tastings-shot-\(name).json"),
            ledgerFile: JSONDocumentStore(filename: "tastings-ledger-shot-\(name).json")
        )
    }

    private static func offer(confidence: CardMatch.Confidence) -> DuplicateOffer {
        let card = CoffeeCard(name: "Chelbesa", roaster: "Fève")
        let pending = PendingScan(
            scan: ScanResult(image: image, quad: .inset(in: CGSize(width: 10, height: 10)), enhance: false),
            card: CoffeeCard(name: "Chelbesa", roaster: "Feve"),
            lines: [],
            parsed: ParsedFields()
        )
        return DuplicateOffer(pending: pending, match: CardMatch.Hit(card: card, confidence: confidence))
    }

    private static let image: CGImage = {
        let context = CGContext(
            data: nil,
            width: 8,
            height: 8,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        return context.makeImage()!
    }()

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

    private static let temp = SeedPlace(
        id: "temp-shop",
        name: "Silo",
        brand: "Silo",
        address: "87 Rue La Fayette, 75009",
        postalCode: "75009",
        arrondissement: 9,
        city: "Paris",
        roasterIDs: [],
        status: .temp,
        closedOn: nil,
        fetchedAt: "2026-10-01"
    )

    private static func hosted<V: View>(_ view: V, tastings: TastingStore? = nil) -> some View {
        let name = UUID().uuidString
        let defaults = UserDefaults(suiteName: "flags-shot-\(name)")!
        return view
        .environment(tastings ?? tastingStore())
        .environment(AIFlags(defaults: defaults))
        .environment(AIEventLog())
        .environment(PlaceIndex(
            places: [],
            notes: JSONDocumentStore(filename: "place-notes-shot-\(name).json")
        ))
        .environment(CardStore(
            files: CardFileStore(url: URL(fileURLWithPath: "/tmp/kohi-tastings-\(name).json"))
        ))
        .environment(RoasterStore(
            files: JSONFileStore(filename: "roasters-shot-\(name).json"),
            seedStamp: JSONDocumentStore(filename: "roaster-stamp-shot-\(name).json")
        ))
    }
}
