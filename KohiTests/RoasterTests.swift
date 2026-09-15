import Foundation
import Testing
@testable import Kohi

/// The roaster index is shared, so its failure mode is not a wrong field on
/// one card — it is three entries for the same roastery, which makes the index
/// worse than the free text it replaced. The dedupe key is what prevents that.
struct RoasterTests {
    private func roaster(_ name: String, _ country: String = "France") -> Roaster {
        Roaster(name: name, country: country)
    }

    /// A store backed by a file nothing else touches, so tests neither read
    /// nor overwrite the real index.
    private func emptyStore() -> RoasterStore {
        RoasterStore(files: JSONFileStore(filename: "roasters-test-\(UUID().uuidString).json"))
    }

    @Test func spellingNoiseFoldsToTheSameKey() {
        let key = roaster("Belleville Brûlerie").dedupeKey
        #expect(roaster("belleville brulerie").dedupeKey == key)
        #expect(roaster("BELLEVILLE BRULERIE").dedupeKey == key)
        #expect(roaster("Belleville  Brûlerie ").dedupeKey == key)
        #expect(roaster("Belleville Brûlerie, Coffee Roasters").dedupeKey == key)
    }

    /// Same name, different country, different roastery. Merging them would
    /// quietly relabel someone's cards.
    @Test func countrySeparatesHomonyms() {
        #expect(roaster("Kaffe", "Norway").dedupeKey != roaster("Kaffe", "Sweden").dedupeKey)
    }

    /// "Coffee Company" is all noise words. Folding it to an empty key would
    /// make it match every other all-noise name.
    @Test func anAllNoiseNameKeepsItself() {
        let generic = roaster("Coffee Company").dedupeKey
        #expect(!generic.hasPrefix("|"))
        #expect(generic != roaster("The Roastery").dedupeKey)
    }

    @Test func addingATwiceReturnsTheFirstEntry() {
        let store = emptyStore()
        let first = store.add(roaster("Belleville Brûlerie"))
        let second = store.add(roaster("belleville brulerie"))

        #expect(first.id == second.id)
        #expect(store.roasters.filter { $0.dedupeKey == first.dedupeKey }.count == 1)
    }

    @Test func suggestionsPreferPrefixMatches() {
        let store = emptyStore()
        let belleville = store.add(roaster("Belleville Brûlerie"))
        _ = store.add(roaster("Cafés de Belleville"))

        let suggestions = store.suggestions(for: "belle")
        #expect(suggestions.first?.id == belleville.id)
        #expect(suggestions.count == 2)
    }

    /// One letter is every roaster; two is a query.
    @Test func suggestionsNeedSomethingToGoOn() {
        let store = emptyStore()
        _ = store.add(roaster("Belleville Brûlerie"))
        #expect(store.suggestions(for: "b").isEmpty)
    }

    /// An ambiguous name is left unmatched: a wrong link is worse than none.
    @Test func matchOnlyWhenUnambiguous() {
        let store = emptyStore()
        _ = store.add(roaster("Belleville Brûlerie", "France"))
        #expect(store.match(name: "Belleville Brûlerie") != nil)

        _ = store.add(roaster("Belleville Brûlerie", "Japan"))
        #expect(store.match(name: "Belleville Brûlerie") == nil)
        #expect(store.match(name: "Belleville Brûlerie", country: "Japan") != nil)
    }

    @Test func rowRoundTripKeepsEveryField() {
        let userID = UUID()
        let original = Roaster(
            name: "Belleville Brûlerie",
            country: "France",
            city: "Paris",
            website: "https://cafesbelleville.com",
            instagram: "@bellevillebrulerie",
            createdBy: userID,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let restored = RoasterRow(roaster: original, userID: userID).toRoaster()
        #expect(restored == original)
    }

    /// Same census contract as the cards: add a field and this fails until it
    /// is mapped in `RoasterRow`.
    @Test func roasterPropertiesAreAllAccountedFor() {
        #expect(
            SyncParityTests.properties(of: roaster("Belleville")) == [
                "id", "name", "country", "city", "website", "instagram",
                "createdBy", "updatedAt",
            ]
        )
    }
}
