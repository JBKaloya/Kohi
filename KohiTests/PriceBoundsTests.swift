import Foundation
import Testing

@testable import Kohi

/// A price follows its currency: up to 99 000 in yen, 999 elsewhere, the
/// same bounds for a cup and a bag, and nothing typed is cut down in silence.
@MainActor
struct PriceBoundsTests {
    @Test func theCurrencyDecidesTheDecimals() {
        #expect(CupPrice.fractionDigits("JPY") == 0)
        #expect(CupPrice.fractionDigits("eur") == 2)
        #expect(CupPrice.fractionDigits("USD") == 2)
    }

    @Test func yenGoesTo99000InTens() {
        let yen = NumberRange.price(in: "JPY")
        #expect(yen.max == 99_000)
        #expect(yen.step == 10)
        #expect(yen.decimals == 0)
        #expect(yen.clamp(1100) == 1100)
        #expect(yen.contains(99_000))
        #expect(!yen.contains(99_001))
    }

    @Test func everyOtherCurrencyGoesTo999InTenCents() {
        for code in CupPrice.commonCurrencies where code != "JPY" {
            let range = NumberRange.price(in: code)
            #expect(range.max == 999, "\(code)")
            #expect(range.step == 0.1, "\(code)")
            #expect(range.decimals == 2, "\(code)")
        }
        #expect(NumberRange.price(in: "EUR").clamp(4.5) == 4.5)
    }

    @Test func aCupAndABagShareTheBounds() {
        for code in CupPrice.commonCurrencies {
            let cup = NumberRange.cupPrice(in: code)
            let bag = NumberRange.price(in: code)
            #expect(cup.max == bag.max && cup.step == bag.step && cup.decimals == bag.decimals)
        }
        #expect(NumberRange.cupPrice(in: "EUR").default == 4)
        #expect(NumberRange.cupPrice(in: "JPY").default == 600)
    }

    @Test func yenReadsThousandsSeparators() {
        #expect(NumberText.parse("1,100", decimals: 0) == 1100)
        #expect(NumberText.parse("1.100", decimals: 0) == 1100)
        #expect(NumberText.parse("1 100", decimals: 0) == 1100)
        #expect(NumberText.parse("1100", decimals: 0) == 1100)
        #expect(NumberText.parse("12,000", decimals: 0) == 12_000)
    }

    @Test func centsStillTakeACommaOrAPoint() {
        #expect(NumberText.parse("4,50", decimals: 2) == 4.5)
        #expect(NumberText.parse("4.50", decimals: 2) == 4.5)
        #expect(NumberText.parse("1.100,50", decimals: 2) == 1100.5)
        #expect(NumberText.parse("1,100.50", decimals: 2) == 1100.5)
    }

    @Test func theKeyboardShowsOnlyTheDecimalsItNeeds() {
        let euro = NumberRange.price(in: "EUR")
        #expect(euro.text(4.55) == "4.55")
        #expect(euro.text(4.5) == "4.5")
        #expect(euro.text(18) == "18")
        #expect(NumberRange.price(in: "JPY").text(1100) == "1100")
    }

    @Test func aYenCupOf1100IsKept() throws {
        var draft = TastingDraft()
        draft.currency = "JPY"
        draft.priceText = String(1100.0)
        let price = try #require(draft.price)
        #expect(price.amount == 1100)
        #expect(price.currency == "JPY")
        #expect(draft.priceNotice == nil)
    }

    @Test func aTypedCommaInYenIsAThousand() {
        var draft = TastingDraft()
        draft.currency = "JPY"
        draft.priceText = "1,100"
        #expect(draft.price?.amount == 1100)
    }

    @Test func changingTheCurrencyNeverConvertsNorCuts() {
        var draft = TastingDraft()
        draft.currency = "JPY"
        draft.priceText = String(1100.0)
        draft.currency = "EUR"
        #expect(draft.price?.amount == 1100)
        #expect(draft.priceNotice == "Over 999 EUR. Check the currency.")
        draft.currency = "JPY"
        #expect(draft.priceNotice == nil)

        var euros = TastingDraft()
        euros.currency = "EUR"
        euros.priceText = String(4.5)
        euros.currency = "JPY"
        #expect(euros.price?.amount == Decimal(string: "4.5"))
    }

    @Test func aMenuPriceGoesThroughTheSameBounds() {
        var yen = TastingDraft()
        yen.apply(MenuField(kind: .price, value: "¥1,100", confidence: .read))
        #expect(yen.price?.amount == 1100)
        #expect(yen.currency == "JPY")

        var euros = TastingDraft()
        euros.apply(MenuField(kind: .price, value: "€4,50", confidence: .read))
        #expect(euros.price?.amount == Decimal(string: "4.5"))
    }

    @Test func aYenPriceSurvivesTheRow() throws {
        let tasting = Tasting(
            context: .out(place: Place(name: "Glitch", address: "", latitude: 0, longitude: 0), placeID: nil),
            price: CupPrice(amount: 1100, currency: "JPY")
        )
        let row = TastingRow(tasting: tasting, userID: UUID())
        let data = try JSONSerialization.data(withJSONObject: SyncParityTests.dictionary(from: row))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(TastingRow.self, from: data).toTasting()
        #expect(decoded.price == CupPrice(amount: 1100, currency: "JPY"))
    }

    @Test func bothPriceFieldsFollowTheCurrency() throws {
        let tasting = try String(contentsOf: DevBrief10.kohiRoot.appending(path: "Tastings/TastingFields.swift"))
        #expect(tasting.contains("range: .cupPrice(in: draft.currency)"))
        #expect(tasting.contains("notice: draft.priceNotice"))
        let card = try String(contentsOf: DevBrief10.kohiRoot.appending(path: "Edit/CardEditSheet.swift"))
        #expect(card.contains("range: .price(in: draft.currency)"))
        let math = try String(contentsOf: DevBrief10.kohiRoot.appending(path: "Design/BrewControlMath.swift"))
        #expect(!math.contains("static let cupPrice"))
        #expect(!math.contains("static let price "))
    }
}
