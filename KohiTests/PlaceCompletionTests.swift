import Foundation
import Testing
@testable import Kohi

/// Country is half of a roaster's dedupe key, so a French spelling and the
/// English one have to land on the same row. Cities follow the index instead
/// of growing a second spelling beside it.
struct PlaceCompletionTests {
    private let indexed = ["France", "Denmark", "United Kingdom", "United States", "Netherlands"]

    @Test func frenchCountryNamesResolveToTheArchiveSpelling() {
        #expect(PlaceCompletion.canonicalCountry("Danemark") == "Denmark")
        #expect(PlaceCompletion.canonicalCountry("  danemark  ") == "Denmark")
        #expect(PlaceCompletion.canonicalCountry("Denmark") == "Denmark")
        #expect(PlaceCompletion.canonicalCountry("Pays-Bas") == "Netherlands")
        #expect(PlaceCompletion.canonicalCountry("États-Unis") == "United States")
        #expect(PlaceCompletion.canonicalCountry("Royaume-Uni") == "United Kingdom")
        #expect(PlaceCompletion.canonicalCountry("uk") == "United Kingdom")
        #expect(PlaceCompletion.canonicalCountry("Atlantis") == "Atlantis")
        #expect(PlaceCompletion.canonicalCountry("  ") == "")
    }

    /// "Den" can only be Denmark. "De" is also the start of Deutschland, and
    /// one letter is not a query. Neither is rewritten on the way out.
    @Test func aUniquePrefixResolvesAndAnAmbiguousOneDoesNot() {
        #expect(PlaceCompletion.canonicalCountry("Den", known: indexed) == "Denmark")
        #expect(PlaceCompletion.canonicalCountry("de", known: indexed) == "de")
        #expect(PlaceCompletion.canonicalCountry("D") == "D")
    }

    @Test func countrySuggestionsLeadWithRoastersAlreadyFiled() {
        #expect(PlaceCompletion.countries(matching: "da", known: indexed) == ["Denmark"])
        #expect(PlaceCompletion.countries(matching: "den", known: indexed) == ["Denmark"])
        #expect(PlaceCompletion.countries(matching: "d", known: indexed).isEmpty)

        let french = PlaceCompletion.countries(matching: "fr", known: indexed)
        #expect(french.first == "France")

        let united = PlaceCompletion.countries(matching: "un", known: indexed)
        #expect(united.contains("United Kingdom"))
        #expect(united.contains("United States"))
        #expect(!united.contains("United Nations"))
        #expect(!united.contains("European Union"))
        let emirates = united.firstIndex(of: "United Arab Emirates")
        let kingdom = united.firstIndex(of: "United Kingdom")
        if let emirates, let kingdom {
            #expect(kingdom < emirates)
        }

        #expect(PlaceCompletion.countries(matching: "Denmark", known: indexed).isEmpty)
        #expect(PlaceCompletion.countries(matching: "roy", known: indexed) == ["United Kingdom"])
        #expect(PlaceCompletion.countries(matching: "pay", known: indexed).first == "Netherlands")
    }

    @Test func anEnglishCityOffersTheSpellingTheIndexUses() {
        let roasters = [
            Roaster(name: "A", country: "Denmark", city: "Copenhague"),
            Roaster(name: "B", country: "Denmark", city: "Copenhague"),
            Roaster(name: "C", country: "Denmark", city: "Aarhus / Copenhague"),
            Roaster(name: "D", country: "France", city: "Paris"),
            Roaster(name: "E", country: "United Kingdom", city: "Londres"),
        ]

        let copenhagen = PlaceCompletion.cities(matching: "Copenhagen", in: roasters, country: "")
        #expect(copenhagen.map(\.title) == ["Copenhague"])
        #expect(copenhagen.first?.country == "Denmark")

        let london = PlaceCompletion.cities(matching: "London", in: roasters, country: "Royaume-Uni")
        #expect(london.map(\.title) == ["Londres"])

        let listed = PlaceCompletion.cities(matching: "", in: roasters, country: "Danemark")
        #expect(listed.map(\.title).contains("Copenhague"))
        #expect(!listed.map(\.title).contains("Paris"))

        #expect(PlaceCompletion.cities(matching: "Pa", in: roasters, country: "Denmark").isEmpty)
        #expect(PlaceCompletion.cities(matching: "Copenhague", in: roasters, country: "Denmark").isEmpty)
        #expect(PlaceCompletion.cities(matching: "P", in: roasters, country: "").isEmpty)
    }

    @Test func aCitySharedByTwoCountriesDoesNotPickOne() {
        let split = [
            Roaster(name: "A", country: "France", city: "Paris"),
            Roaster(name: "B", country: "Brazil", city: "Paris"),
        ]
        let even = PlaceCompletion.cities(matching: "Pa", in: split, country: "")
        #expect(even.map(\.title) == ["Paris"])
        #expect(even.first?.country == nil)

        let france = (0..<3).map { Roaster(name: "f\($0)", country: "France", city: "Paris") }
        let majority = PlaceCompletion.cities(
            matching: "Pa",
            in: france + [Roaster(name: "b", country: "Brazil", city: "Paris")],
            country: ""
        )
        #expect(majority.first?.country == "France")
    }
}
