import Foundation
import Testing

@testable import Kohi

/// Build 13: editable counters, a slider that follows the finger, the pack's
/// flavours as chips, one currency picker that starts where you are, a
/// narrower dictation, and a scan module whose model calls all answer for
/// themselves.

struct CounterKeyboardTests {
    @Test func aCommaIsADecimalSeparator() {
        #expect(NumberText.parse("4,5") == 4.5)
        #expect(NumberText.parse("12.") == 12)
        #expect(NumberText.parse(" 250 ") == 250)
        #expect(NumberText.parse("") == nil)
        #expect(NumberText.parse("abc") == nil)
    }

    @Test func typedValuesLandInsideTheRange() {
        #expect(NumberRange.price.clamp(1200) == 999)
        #expect(NumberRange.agtron.clamp(70.4) == 70)
        #expect(NumberRange.dose.clamp(15.26) == 15.3)
        #expect(NumberRange.bagWeight.clamp(10) == 50)
    }

    /// The field is shown first and takes focus once it exists. Focus that
    /// also decided whether the field existed never landed.
    @Test func showingTheFieldIsNotTheFocus() throws {
        let source = try String(contentsOf: DevBrief10.kohiRoot.appending(path: "Design/RollingCounter.swift"))
        #expect(source.contains("@State private var editing = false"))
        #expect(source.contains("@FocusState private var focused: Bool"))
        #expect(source.contains(".focused($focused)"))
        #expect(source.contains(".onAppear { focused = true }"))
        #expect(!source.contains("@FocusState private var editing"))
    }

    @Test func sheetsOutsideStepFlowHaveADoneKey() throws {
        for file in [
            "Edit/CardEditSheet.swift",
            "Recipes/RecipeEditSheet.swift",
            "Recipes/StepBuilderSheet.swift",
            "Setup/EquipmentSheet.swift",
            "Setup/WaterSheet.swift",
            "Setup/GrindConverterSheet.swift",
            "Tastings/TastingComposeSheet.swift",
        ] {
            let text = try String(contentsOf: DevBrief10.kohiRoot.appending(path: file))
            #expect(text.contains(".keyboardDoneButton()"), "no Done key in \(file)")
        }
    }
}

struct SloshLiveValueTests {
    @Test func theFingerSnapsToWholeScores() {
        #expect(SloshSim.snap(0) == 0)
        #expect(SloshSim.snap(54) == 5)
        #expect(SloshSim.snap(56) == 6)
        #expect(SloshSim.snap(100) == 10)
        #expect(SloshSim.snap(-20) == 0)
        #expect(SloshSim.snap(140) == 10)
    }

    @Test func theBindingFollowsTheDrag() throws {
        let source = try String(contentsOf: DevBrief10.kohiRoot.appending(path: "Design/SloshRail.swift"))
        #expect(source.contains("set(SloshSim.snap(percent))"))
        #expect(source.contains("startValue = value"))
        #expect(source.contains("set(startValue == snapped ? nil : snapped)"))
    }
}

struct QuickFlavorTests {
    private static func tags(_ ids: [String]) -> [FlavorTag] { ids.map { FlavorTag(id: $0) } }
    private static let standard = tags((1...30).map { "std-\($0)" })

    @Test func whatThePackSaysIsNotRepeated() {
        let quick = QuickFlavors.compose(
            recent: Self.tags(["lemon"]),
            standard: Self.tags(["lemon", "cocoa", "honey"]),
            declared: Self.tags(["lemon", "honey"]),
            selection: []
        )
        #expect(quick.map(\.id) == ["cocoa"])
    }

    @Test func recentComesBeforeTheStandardSet() {
        let quick = QuickFlavors.compose(
            recent: Self.tags(["jasmine", "std-3"]),
            standard: Self.standard,
            declared: [],
            selection: []
        )
        #expect(quick.prefix(3).map(\.id) == ["jasmine", "std-3", "std-1"])
        #expect(quick.filter { $0.id == "std-3" }.count == 1)
    }

    @Test func theRowStopsAtTwelve() {
        let quick = QuickFlavors.compose(recent: [], standard: Self.standard, declared: [], selection: [])
        #expect(quick.count == QuickFlavors.cap)
        #expect(QuickFlavors.cap == 12)
    }

    /// The summary above the picker is text, so a ticked flavour past the cap
    /// keeps its chip, or it could never be unticked.
    @Test func aTickedFlavourPastTheCapStaysVisible() {
        let quick = QuickFlavors.compose(
            recent: [],
            standard: Self.standard,
            declared: Self.tags(["lemon"]),
            selection: Self.tags(["molasses", "std-20", "lemon", "std-2"])
        )
        let ids = quick.map(\.id)
        #expect(ids.contains("molasses"))
        #expect(ids.contains("std-20"))
        #expect(!ids.contains("lemon"))
        #expect(ids.filter { $0 == "std-2" }.count == 1)
        #expect(ids.count == QuickFlavors.cap + 2)
    }

    @Test func thePackChipsToggleTheSelection() throws {
        let blocks = try String(contentsOf: DevBrief10.kohiRoot.appending(path: "Design/TastingBlocks.swift"))
        #expect(!blocks.contains("TagChip(text: tag.displayName, isSelected: false) {}"))
        #expect(blocks.contains("declaredChip(tag)"))
        #expect(blocks.contains("FlavorPicker(selection: $selection, recent: recent, declared: declared)"))
    }
}

struct CurrencyTests {
    @Test func aCountryHasACurrency() {
        #expect(LocalCurrency.currency(forCountry: "JP") == "JPY")
        #expect(LocalCurrency.currency(forCountry: "US") == "USD")
        #expect(LocalCurrency.currency(forCountry: "GB") == "GBP")
        #expect(LocalCurrency.currency(forCountry: "FR") == "EUR")
        #expect(LocalCurrency.currency(forCountry: "br") == "BRL")
        #expect(LocalCurrency.currency(forCountry: "ZZ") == nil)
        #expect(LocalCurrency.currency(forCountry: "AQ") == nil)
    }

    @Test func whereYouAreComesFirst() {
        #expect(LocalCurrency.proposed(countryCode: "JP", phoneCurrency: "EUR") == "JPY")
    }

    @Test func withoutAPositionThePhoneDecides() {
        #expect(LocalCurrency.proposed(countryCode: nil, phoneCurrency: "USD") == "USD")
        #expect(LocalCurrency.proposed(countryCode: "ZZ", phoneCurrency: "usd") == "USD")
    }

    @Test func withNeitherItIsEuros() {
        #expect(LocalCurrency.proposed(countryCode: nil, phoneCurrency: nil) == "EUR")
        #expect(LocalCurrency.proposed(countryCode: nil, phoneCurrency: "") == "EUR")
    }

    @MainActor
    @Test func theCountryIsRememberedAcrossLaunches() {
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        defaults.set("JP", forKey: "kohi.localCurrency.country")
        #expect(LocalCurrency(defaults: defaults).proposed == "JPY")
    }

    @Test func aCurrencyOutsideTheListGetsItsOwnChip() {
        #expect(CurrencyPicker.options(including: nil) == CupPrice.commonCurrencies)
        #expect(CurrencyPicker.options(including: "EUR") == CupPrice.commonCurrencies)
        #expect(CurrencyPicker.options(including: "BRL") == ["BRL"] + CupPrice.commonCurrencies)
    }

    @Test func bothScreensUseTheOnePicker() throws {
        let card = try String(contentsOf: DevBrief10.kohiRoot.appending(path: "Edit/CardEditSheet.swift"))
        let tasting = try String(contentsOf: DevBrief10.kohiRoot.appending(path: "Tastings/TastingFields.swift"))
        #expect(card.contains("CurrencyPicker(code: $draft.currency)"))
        #expect(!card.contains("currencyPicks"))
        #expect(tasting.contains("CurrencyPicker(code: $draft.currency)"))
        #expect(!tasting.contains("Button(code) { draft.currency = code }"))
    }
}

struct CoffeeLexiconTests {
    @Test func theListIsDedupedAndClipped() {
        let terms = ["V60", "v60", " Kalita ", "", "a"] + (1...200).map { "term \($0)" }
        let clipped = CoffeeLexicon.clip(terms)
        #expect(clipped.count == CoffeeLexicon.cap)
        #expect(Array(clipped.prefix(3)) == ["V60", "Kalita", "term 1"])
    }

    @Test func theNewestCoffeesLead() {
        var older = CoffeeCard(name: "Old Lot", roaster: "Slow Roasters")
        older.updatedAt = .distantPast
        var newer = CoffeeCard(name: "Chelbesa", roaster: "Kawa")
        newer.updatedAt = .now
        let terms = CoffeeLexicon.coffees(cards: [older, newer], roasters: ["Kawa", "Belleville"])
        #expect(terms == ["Chelbesa", "Kawa", "Old Lot", "Slow Roasters", "Belleville"])
    }

    @Test func recipeNamingHearsTheMethods() {
        let terms = CoffeeLexicon.recipes([])
        #expect(terms.contains(BrewMethod.v60.label))
    }

    @Test func theVocabularyReachesEveryRequest() throws {
        let dictation = try String(contentsOf: DevBrief10.kohiRoot.appending(path: "Scan/Dictation.swift"))
        #expect(dictation.contains("request.contextualStrings = contextualStrings"))
        let field = try String(contentsOf: DevBrief10.kohiRoot.appending(path: "Design/DictationField.swift"))
        #expect(field.contains("dictation.contextualStrings = vocabulary()"))
        let transcriber = try String(contentsOf: DevBrief10.kohiRoot.appending(path: "Scan/VoiceNoteTranscriber.swift"))
        #expect(!transcriber.contains("contextualStrings"))
    }
}

struct ScanPipelineTests {
    @Test func onlyTheModelsValuesThatLandedCount() {
        let landed = ModelFill.landed(
            model: ["name": "Chelbesa", "country": "Ethiopia", "process": "Washed"],
            before: ["name": "Typed by you"],
            after: ["name": "Typed by you", "country": "Ethiopia", "process": "Washed"]
        )
        #expect(landed == ["country": "Ethiopia", "process": "Washed"])
    }

    @Test func keptMeansAtLeastOneValueSurvivedTheSave() {
        let fill = ModelFill(eventID: UUID(), values: ["country": "Ethiopia", "process": "Washed"])
        #expect(fill.kept(in: ["country": "Ethiopia", "process": "Natural"]))
        #expect(!fill.kept(in: ["country": "Kenya"]))
        #expect(!fill.kept(in: [:]))
        #expect(!ModelFill(eventID: UUID(), values: [:]).kept(in: ["country": "Ethiopia"]))
    }

    @Test func aCardAndAParseShareTheirKeys() {
        var parsed = ParsedFields()
        parsed.name = "Chelbesa"
        parsed.price = 18
        parsed.tastingNotes = ["Jasmine", "Peach"]
        var card = CoffeeCard(name: "Chelbesa", roaster: "")
        card.price = 18
        card.tastingNotes = ["Jasmine", "Peach"]
        let fromParse = FieldValues.of(parsed)
        let fromCard = FieldValues.of(card)
        for key in fromParse.keys {
            #expect(fromParse[key] == fromCard[key], "\(key) differs")
        }
    }

    @Test func theEnrichmentLeftRootView() throws {
        let root = try String(contentsOf: DevBrief10.kohiRoot.appending(path: "App/RootView.swift"))
        #expect(!root.contains("enum ScanEnrichment"))
        #expect(root.contains("ScanPipeline.fields(of: pending"))
        let vision = try String(contentsOf: DevBrief10.kohiRoot.appending(path: "Process/CardVision.swift"))
        #expect(vision.contains("static func read(cardID: UUID) async -> Reading?"))
        #expect(vision.contains("static func read(image: CGImage) async -> Reading?"))
        #expect(vision.contains("feature: .cardVision"))
    }

    /// A café cup has no QR and no product page: the tasting path never
    /// reaches for either.
    @Test func theTastingPathSkipsCodesAndLinks() throws {
        let reader = try String(contentsOf: DevBrief10.kohiRoot.appending(path: "Tastings/TastingFields.swift"))
        #expect(reader.contains("ScanPipeline.secondOpinion("))
        #expect(!reader.contains("LabelCodeReader"))
        #expect(!reader.contains("LabelLink"))
    }

    @Test func readingAMenuIsNative() throws {
        #expect(!AIFeature.menuExtract.isExperimental)
        #expect(!AIFeature.cardVision.isExperimental)
        for file in ["Tastings/TastingFlow.swift", "Tastings/TastingComposeSheet.swift"] {
            let text = try String(contentsOf: DevBrief10.kohiRoot.appending(path: file))
            #expect(!text.contains("canAskModel: flags.isOn(.menuExtract)"), "\(file) still gates the menu read")
        }
    }

    @MainActor
    @Test func aRefusedMenuReadStaysRefused() {
        let flags = AIFlags(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
        flags.isExperimentalEnabled = false
        #expect(flags.isOn(.menuExtract))
        flags.setOn(.menuExtract, false)
        #expect(!flags.isOn(.menuExtract))
    }
}
