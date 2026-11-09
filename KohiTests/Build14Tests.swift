import CoreGraphics
import Foundation
import Testing

@testable import Kohi

/// Build 14: the roaster index under every roaster field, and the currency
/// back to one control that opens the list.

struct RoasterEverywhereTests {
    private func emptyStore() -> RoasterStore {
        let name = UUID().uuidString
        return RoasterStore(
            files: JSONFileStore(filename: "roasters-test-\(name).json"),
            seedStamp: JSONDocumentStore(filename: "roaster-seed-stamp-test-\(name).json")
        )
    }

    private func seed(_ slug: String, _ name: String, aliases: [String] = [], fetchedAt: String = "2026-11-08") -> RoasterSeed {
        RoasterSeed(
            slug: slug, name: name, country: "Japan", city: "Tokyo",
            website: nil, instagram: nil, parisShopsServed: 0, ownShopIDs: [],
            aliases: aliases, sources: [], status: "", note: "", fetchedAt: fetchedAt
        )
    }

    @Test func theSeedIsOfferedByNameAndAlias() {
        let store = emptyStore()
        store.applySeed([seed("raw-sugar", "Raw Sugar Roast", aliases: ["rawsugar"])])
        #expect(store.suggestions(for: "raw").map(\.name) == ["Raw Sugar Roast"])
        #expect(store.suggestions(for: "rawsu").map(\.name) == ["Raw Sugar Roast"])
    }

    @Test func applyingTheSeedTwiceAddsNothing() {
        let store = emptyStore()
        let rows = [seed("raw-sugar", "Raw Sugar Roast")]
        store.applySeed(rows)
        store.applySeed(rows.map { var row = $0; row.fetchedAt = "2026-11-09"; return row })
        #expect(store.roasters.filter { $0.seedID == "raw-sugar" }.count == 1)
    }

    @Test func bothTastingScreensUseTheSharedField() throws {
        let compose = try String(contentsOf: DevBrief10.kohiRoot.appending(path: "Tastings/TastingComposeSheet.swift"))
        let field = try String(contentsOf: DevBrief10.kohiRoot.appending(path: "Tastings/TastingFields.swift"))
        #expect(compose.contains("TastingRoasterField(draft: $draft)"))
        #expect(field.contains("TastingRoasterField(draft: $draft)"))
        #expect(!compose.contains("TastingTextField(label: \"Roaster\""))
        #expect(field.components(separatedBy: "TastingTextField(label: \"Roaster\"").count == 2)
        #expect(field.contains("roasters.suggestions(for: typed)"))
        #expect(field.contains("places.servedRoasterIDs(for: placeID)"))
    }

    @Test func addingARoasterOffersTheOnesAlreadyIndexed() throws {
        let sheet = try String(contentsOf: DevBrief10.kohiRoot.appending(path: "Edit/RoasterSheet.swift"))
        #expect(sheet.contains("completions: nameOffers.map(\\.name)"))
    }
}

struct CompactCurrencyTests {
    /// One element on screen, the ten codes behind a tap, not ten chips.
    @Test func thePickerIsOneControl() throws {
        let picker = try String(contentsOf: DevBrief10.kohiRoot.appending(path: "Design/CurrencyPicker.swift"))
        #expect(picker.contains("Menu {"))
        #expect(!picker.contains("FlowLayout"))
        #expect(picker.contains(".touchTarget()"))
    }

    /// Only the card can be left without a currency.
    @Test func noCurrencyIsACardChoice() throws {
        let picker = try String(contentsOf: DevBrief10.kohiRoot.appending(path: "Design/CurrencyPicker.swift"))
        #expect(picker.contains("if allowsNone {"))
        #expect(picker.contains("allowsNone: false"))
    }

    /// Beside the price, in the same well as the counter, on both screens.
    /// On the card it waits for a price before it opens.
    @Test func eachScreenPlacesItBesideThePrice() throws {
        let tasting = try String(contentsOf: DevBrief10.kohiRoot.appending(path: "Tastings/TastingFields.swift"))
        #expect(tasting.contains("CounterRow(\n                value:"))
        #expect(tasting.contains("range: .cupPrice(in: draft.currency)"))
        #expect(!tasting.contains("TextField(\"0,00\""))
        let card = try String(contentsOf: DevBrief10.kohiRoot.appending(path: "Edit/CardEditSheet.swift"))
        #expect(card.contains("CounterRow(\n            \"Price\""))
        #expect(card.contains(".disabled(draft.price == nil)"))
        let picker = try String(contentsOf: DevBrief10.kohiRoot.appending(path: "Design/CurrencyPicker.swift"))
        #expect(picker.contains("WellMenuLabel(text:"))
    }
}

/// Build 14: a row of options stays on one line; what you own still wraps.
struct ChipRailTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOf: DevBrief10.kohiRoot.appending(path: path))
    }

    @Test func pickersAreOneLine() throws {
        let form = try source("Design/FormField.swift")
        let picker = try #require(form.range(of: "struct ChipPicker"))
        let toggles = try #require(form.range(of: "struct ChipToggles"))
        #expect(form[picker.lowerBound..<toggles.lowerBound].contains("ChipRail {"))
        #expect(form[toggles.lowerBound...].contains("ChipRail {"))
    }

    @Test func theBagAndTheMethodAreOneLine() throws {
        let card = try source("Edit/CardEditSheet.swift")
        let bag = try #require(card.range(of: "private var bagWeightPicker"))
        #expect(card[bag.lowerBound...].prefix(900).contains("ChipRail {"))
        #expect(card[bag.lowerBound...].prefix(900).contains("hint: draft.pricePerKilo"))
        let fields = try source("Tastings/TastingFields.swift")
        let method = try #require(fields.range(of: "private var methodPicker"))
        let body = fields[method.lowerBound...].prefix(1400)
        #expect(!body.contains("FlowLayout"))
        #expect(body.components(separatedBy: "Rectangle().fill(Palette.hairline)").count == 3)
    }

    @Test func yourOwnTagsStillWrap() throws {
        #expect(try source("Edit/TagField.swift").contains("ForEach(tags, id: \\.self)"))
        let fields = try source("Tastings/TastingFields.swift")
        let notes = try #require(fields.range(of: "struct TastingNotesField"))
        #expect(fields[notes.lowerBound...].prefix(1200).contains("FlowLayout {"))
    }
}

/// Build 14 (Q4, Q5): codes and the product link on a tasting's card.
struct TastingCodesTests {
    private func code(_ payload: String) -> LabelCodeReader.Found {
        LabelCodeReader.Found(payload: payload, bounds: .zero)
    }

    @Test func anOpaqueCodeIsKeptWithoutAFetch() async {
        let parsed = await ScanPipeline.linked(codes: [code("3760123456789")], local: ParsedFields())
        #expect(parsed.labelCode == "3760123456789")
        #expect(parsed.productURL == nil)
    }

    @Test func aLinkWinsOverAnOpaqueCode() async {
        let parsed = await ScanPipeline.linked(
            codes: [code("3760123456789"), code("https://instagram.com/rawsugarroast")],
            local: ParsedFields()
        )
        #expect(parsed.productURL == "https://instagram.com/rawsugarroast")
        #expect(parsed.name == nil)
    }

    @Test func whatWasReadIsNeverReplaced() async {
        var local = ParsedFields()
        local.name = "Bulga West Arsi"
        local.productURL = "https://rawsugar.example/bulga"
        let parsed = await ScanPipeline.linked(codes: [code("https://instagram.com/x")], local: local)
        #expect(parsed.name == "Bulga West Arsi")
        #expect(parsed.productURL == "https://rawsugar.example/bulga")
    }

    @Test func noCodeChangesNothing() async {
        var local = ParsedFields()
        local.roaster = "Raw Sugar"
        #expect(await ScanPipeline.linked(codes: [], local: local) == local)
    }
}
