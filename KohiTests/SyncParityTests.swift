import Foundation
import Testing
@testable import Kohi

/// The promise is that everything typed into Kohi reaches Supabase. That only
/// holds if every stored property of a model has a column and a mapping in both
/// directions.
///
/// Two guards, because either one alone is easy to fool:
///
/// 1. A round trip through the row DTO, from a fixture where no field holds its
///    default value — so a dropped field shows up as an inequality.
/// 2. A property census. Add a field to a model and this fails immediately,
///    which is the nudge to map it and extend the fixture. Without it, a new
///    field would simply never be covered by (1).
struct SyncParityTests {
    static let userID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    // MARK: - Fixtures

    /// Every field set, and none of them left at its default.
    static func fullBrew() -> Brew {
        Brew(
            id: UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!,
            date: Date(timeIntervalSince1970: 1_700_000_000),
            method: .v60,
            dose: 15.5,
            water: 250,
            beverage: 232,
            seconds: 165,
            grind: "22 clicks",
            temperature: 93.5,
            tds: 1.38,
            recipeID: UUID(uuidString: "EEEEEEEE-0000-0000-0000-000000000001")!,
            recipeRef: "ref:a1-v60-ultimate",
            recipeSnapshot: RecipeSnapshot(
                from: Recipe(
                    name: "V60 « Ultimate »",
                    method: .v60,
                    dose: 30,
                    water: 500,
                    referenceID: "a1-v60-ultimate"
                )
            ),
            scale: .cup,
            equipmentIDs: [UUID(uuidString: "EEEEEEEE-0000-0000-0000-000000000002")!],
            waterProfileID: UUID(uuidString: "EEEEEEEE-0000-0000-0000-000000000003")!,
            agitation: .swirl,
            filterStockId: UUID(uuidString: "EEEEEEEE-0000-0000-0000-000000000005")!,
            steps: [
                BrewStep(
                    id: UUID(uuidString: "EEEEEEEE-0000-0000-0000-000000000004")!,
                    index: 0,
                    action: .bloom,
                    at: 3,
                    mass: 60,
                    targetAt: 0,
                    targetMass: 60,
                    note: "swirled"
                )
            ],
            plannedSteps: [
                BrewStep(
                    id: UUID(uuidString: "EEEEEEEE-0000-0000-0000-000000000006")!,
                    index: 0,
                    action: .bloom,
                    at: 0,
                    targetAt: 45,
                    targetMass: 60
                )
            ],
            actualSource: .timer,
            flowGs: 1.5,
            recipeName: "V60 « Ultimate »",
            pourRates: [PourRate(stepIndex: 1, grams: 60, seconds: 15, gPerS: 4)],
            taste: TasteProfile(acidity: 6, bitterness: 4, sweetness: 8, aroma: 8, aftertaste: 8, body: 4, clarity: 7),
            flavors: [
                FlavorTag(id: "floral-floral-jasmine"),
                FlavorTag(id: "fruity-other-fruit-peach"),
            ],
            nextTimeSuggestion: "grind two clicks finer",
            captureSource: .dictated,
            rating: 4,
            acidity: -1,
            bitterness: 1,
            body: -1,
            complexity: 1,
            notes: "bloomed longer"
        )
    }

    static func fullCard() -> CoffeeCard {
        CoffeeCard(
            id: UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000001")!,
            name: "Chelbesa",
            roaster: "Belleville",
            roasterId: UUID(uuidString: "DDDDDDDD-0000-0000-0000-000000000001")!,
            place: Place(
                name: "Belleville Brûlerie",
                address: "10 rue Pradier, Paris",
                latitude: 48.8722,
                longitude: 2.3819
            ),
            placeID: "crible",
            placeType: .roastery,
            country: "Ethiopia",
            region: "Gedeb",
            producer: "Chelbesa washing station",
            altitude: "2100m",
            variety: "Heirloom",
            process: "Washed",
            tastingNotes: ["jasmine", "peach"],
            brewMethod: .v60,
            personalNotes: "keep for mornings",
            brews: [fullBrew()],
            tastings: [
                Tasting(
                    id: UUID(uuidString: "FFFFFFFF-0000-0000-0000-000000000001")!,
                    date: Date(timeIntervalSince1970: 1_700_000_200),
                    context: .out(
                        place: Place(
                            name: "Crible",
                            address: "75 Rue Buffon",
                            latitude: 48.8412,
                            longitude: 2.3614
                        ),
                        placeID: "crible"
                    ),
                    rating: 5,
                    taste: TasteProfile(acidity: 7, sweetness: 6),
                    flavors: [FlavorTag(custom: "Jasmine")],
                    acidity: 1,
                    bitterness: -1,
                    body: 1,
                    note: "at the bar",
                    createdAt: Date(timeIntervalSince1970: 1_700_000_200),
                    updatedAt: Date(timeIntervalSince1970: 1_700_000_200)
                ),
                Tasting(
                    id: UUID(uuidString: "FFFFFFFF-0000-0000-0000-000000000002")!,
                    date: Date(timeIntervalSince1970: 1_700_000_300),
                    context: .home(brewID: nil),
                    rating: 3,
                    createdAt: Date(timeIntervalSince1970: 1_700_000_300),
                    updatedAt: Date(timeIntervalSince1970: 1_700_000_300)
                ),
            ],
            attachments: [
                CardAttachment(
                    id: UUID(uuidString: "CCCCCCCC-0000-0000-0000-000000000001")!,
                    role: .recipe,
                    caption: "back of the card",
                    aspectRatio: 0.8,
                    createdAt: Date(timeIntervalSince1970: 1_700_000_100)
                )
            ],
            species: .robusta,
            isDecaf: true,
            decafMethod: .swissWater,
            productURL: "https://example.com/chelbesa-shop",
            farm: "Chelbesa",
            washStation: "Gedeb station",
            roastLevel: .mediumLight,
            agtron: 62,
            roastedOn: Date(timeIntervalSince1970: 1_698_500_000),
            harvest: "2025/26",
            cuppingScore: 87.5,
            price: 18.5,
            currency: "EUR",
            bagWeightG: 250,
            lot: "24-118",
            labelCode: "https://example.com/chelbesa",
            recipeSuggestion: fullBrew(),
            sourceLanguage: "ja",
            originalFields: ["name": "チェルベサ"],
            date: Date(timeIntervalSince1970: 1_699_000_000),
            createdAt: Date(timeIntervalSince1970: 1_698_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_701_000_000),
            aspectRatio: 0.72,
            hasMask: true,
            enhanced: true,
            poster: .ready
        )
    }

    // MARK: - Round trips

    @Test func cardSurvivesTheRowRoundTrip() {
        let original = Self.fullCard()
        let row = CardRow(card: original, userID: Self.userID)
        let restored = row.toCoffeeCard(brews: original.brews)

        #expect(restored == original)
    }

    @Test func brewSurvivesTheRowRoundTrip() {
        let original = Self.fullBrew()
        let restored = BrewRow(
            brew: original,
            cardID: Self.fullCard().id,
            userID: Self.userID
        ).toBrew()

        #expect(restored == original)
    }

    /// The pull decodes `coffee_cards` joined with `brews(*)`. It used to use a
    /// hand-rolled struct that quietly skipped three columns; this pins the
    /// join to `CardRow`.
    @Test func pullDecodesEveryColumnThroughCardRow() throws {
        let card = Self.fullCard()
        let row = CardRow(card: card, userID: Self.userID)
        let brewRows = card.brews.map {
            BrewRow(brew: $0, cardID: card.id, userID: Self.userID)
        }

        var json = try Self.dictionary(from: row)
        json["brews"] = try brewRows.map { try Self.dictionary(from: $0) }

        let data = try JSONSerialization.data(withJSONObject: json)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let joined = try decoder.decode(CardWithBrews.self, from: data)

        let restored = joined.row.toCoffeeCard(brews: joined.brews.map { $0.toBrew() })

        #expect(restored == card)
        #expect(restored.recipeSuggestion == card.recipeSuggestion)
        #expect(restored.sourceLanguage == card.sourceLanguage)
        #expect(restored.originalFields == card.originalFields)
    }

    // MARK: - Property census

    /// If this fails, a field was added to `CoffeeCard`. Map it in `CardRow`,
    /// add the column, extend `fullCard()`, then list it here.
    @Test func coffeeCardPropertiesAreAllAccountedFor() {
        #expect(
            Self.properties(of: Self.fullCard()) == [
                "id", "name", "roaster", "roasterId", "place", "placeID", "placeType",
                "country", "region", "producer", "altitude", "variety", "process",
                "tastingNotes", "brewMethod", "personalNotes", "brews", "tastings",
                "attachments", "species", "isDecaf", "decafMethod", "productURL",
                "farm", "washStation", "roastLevel", "agtron",
                "roastedOn", "harvest", "cuppingScore", "price", "currency",
                "bagWeightG", "lot", "labelCode", "recipeSuggestion",
                "sourceLanguage", "originalFields", "date", "createdAt",
                "updatedAt", "aspectRatio", "hasMask", "enhanced", "poster",
            ]
        )
    }

    /// Same contract for `Brew`, mapped by `BrewRow`.
    @Test func brewPropertiesAreAllAccountedFor() {
        #expect(
            Self.properties(of: Self.fullBrew()) == [
                "id", "date", "method", "dose", "water", "beverage", "seconds",
                "grind", "temperature", "tds", "recipeID", "recipeRef", "recipeSnapshot",
                "scale", "equipmentIDs",
                "waterProfileID", "agitation", "filterStockId", "steps", "plannedSteps",
                "actualSource", "flowGs", "recipeName", "pourRates",
                "taste", "legacyTaste", "flavors",
                "nextTimeSuggestion", "captureSource", "rating", "acidity",
                "bitterness", "body", "complexity", "notes",
            ]
        )
    }

    // MARK: - Tastings

    static func fullTasting() -> Tasting {
        Tasting(
            id: UUID(uuidString: "FFFFFFFF-0000-0000-0000-000000000010")!,
            date: Date(timeIntervalSince1970: 1_700_000_400),
            context: .out(
                place: Place(
                    name: "Crible",
                    address: "75 Rue Buffon",
                    latitude: 48.8412,
                    longitude: 2.3614,
                    mapItemID: "I1234",
                    city: "Paris",
                    country: "France"
                ),
                placeID: "crible"
            ),
            cardID: fullCard().id,
            coffee: TastedCoffee(
                name: "Sidra",
                roaster: "Fève",
                roasterId: UUID(uuidString: "DDDDDDDD-0000-0000-0000-000000000002")!,
                country: "Colombia",
                region: "Huila",
                farm: "La Palma",
                variety: "Sidra",
                process: "Natural",
                tastingNotes: ["strawberry"],
                referenceID: "ref-1"
            ),
            method: .filter,
            brewer: .v60,
            isBatch: true,
            methodNote: "Orea",
            price: CupPrice(amount: Decimal(string: "5.50")!, currency: "EUR"),
            photos: ["cup.heic"],
            rating: 4,
            taste: TasteProfile(acidity: 7, sweetness: 6),
            flavors: [FlavorTag(custom: "Strawberry")],
            acidity: 1,
            bitterness: -1,
            body: 1,
            note: "at the bar",
            createdAt: Date(timeIntervalSince1970: 1_700_000_500),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_600),
            deletedAt: Date(timeIntervalSince1970: 1_700_000_700)
        )
    }

    @Test func tastingSurvivesTheRowRoundTrip() throws {
        let original = Self.fullTasting()
        let row = TastingRow(tasting: original, userID: Self.userID)
        #expect(row.toTasting() == original)

        let data = try JSONSerialization.data(withJSONObject: Self.dictionary(from: row))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(TastingRow.self, from: data)
        #expect(decoded.toTasting() == original)
    }

    @Test func aSoftDeleteTravelsAsDeletedAt() {
        let row = TastingRow(tasting: Self.fullTasting(), userID: Self.userID)
        #expect(row.deleted_at == Date(timeIntervalSince1970: 1_700_000_700))
        #expect(row.toTasting().isDeleted)
    }

    @Test func aLegacyHomeTastingKeepsItsContext() {
        let home = Tasting(context: .home(brewID: UUID()), rating: 3)
        let restored = TastingRow(tasting: home, userID: Self.userID).toTasting()
        #expect(restored.context == home.context)
    }

    /// If this fails, a field was added to `Tasting`. Map it in `TastingRow`,
    /// add the column, extend `fullTasting()`, then list it here.
    @Test func tastingPropertiesAreAllAccountedFor() {
        #expect(
            Self.properties(of: Self.fullTasting()) == [
                "id", "date", "context", "cardID", "coffee", "method", "brewer",
                "isBatch", "methodNote", "price", "photos", "rating", "taste",
                "flavors", "acidity", "bitterness", "body", "note", "createdAt",
                "updatedAt", "deletedAt",
            ]
        )
        #expect(
            Self.properties(of: Self.fullTasting().coffee) == [
                "name", "roaster", "roasterId", "country", "region", "farm",
                "variety", "process", "tastingNotes", "referenceID",
            ]
        )
    }

    @Test func caffeineIsGone() {
        #expect(!Self.properties(of: Self.fullBrew()).contains("caffeineOverrideMg"))
    }

    // MARK: - Helpers

    static func properties(of value: Any) -> Set<String> {
        Set(Mirror(reflecting: value).children.compactMap(\.label))
    }

    static func dictionary(from value: some Encodable) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        let object = try JSONSerialization.jsonObject(with: data)
        return object as? [String: Any] ?? [:]
    }
}
