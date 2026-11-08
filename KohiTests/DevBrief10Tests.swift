import CoreGraphics
import Foundation
import Testing
import SwiftUI
@testable import Kohi

/// Lot 10: two-column grid, tabbed card detail, tasting flow, scan intent.

struct GridLaunchTests {
    @Test func everyLaunchOpensOnTwoColumns() throws {
        #expect(GridDensity.launch == .two)
        let grid = try String(contentsOf: DevBrief10.kohiRoot.appending(path: "Grid/GridScreen.swift"))
        #expect(grid.contains("GridDensity = .launch"))
        #expect(!grid.contains("AppStorage(\"grid"))
    }

    @Test func thePinchStillStepsFromOneToFour() {
        #expect(GridDensity.two.stepped(by: 2) == .one)
        #expect(GridDensity.two.stepped(by: 0.5) == .four)
        #expect(GridDensity.two.stepped(by: 0.66) == .three)
        #expect(GridDensity.two.stepped(by: 1) == .two)
    }
}

struct CardDetailTabTests {
    private static let brewBlocks: Set<CardDetailSection> = [.profile, .brewLog, .noBrews, .tastedAt]
    private static let cardActions: Set<CardDetailSection> = [.actions, .kitPrompt, .recipes]

    private static func card(brews: Int) -> CoffeeCard {
        var card = CoffeeCard(name: "Geisha", roaster: "Zoma", country: "Colombia")
        card.tastingNotes = ["Jasmine"]
        card.personalNotes = "Grind finer"
        card.brews = (0..<brews).map { _ in Brew(method: .v60, dose: 15, water: 250, rating: 4) }
        return card
    }

    private static let everything = CardDetailSections.Flags(
        hasRecipe: true, kitIsEmpty: true, showsProfile: true, tastedCount: 1
    )

    @Test func coffeeHoldsTheCardAndNoBrew() {
        let sections = CardDetailSections.ordered(for: .coffee, card: Self.card(brews: 6), flags: Self.everything)
        #expect(Set(sections).isDisjoint(with: Self.brewBlocks))
        #expect(sections.first == .notes)
        #expect(sections.last == .actions)
        #expect(sections.contains(.recipes))
    }

    @Test func brewsHoldsTheBrewsAndNoCardAction() {
        let sections = CardDetailSections.ordered(for: .brews, card: Self.card(brews: 6), flags: Self.everything)
        #expect(Set(sections).isDisjoint(with: Self.cardActions))
        #expect(sections == [.profile, .brewLog, .tastedAt])
    }

    @Test func brewsWithoutABrewSaysSo() {
        let sections = CardDetailSections.ordered(for: .brews, card: Self.card(brews: 0), flags: .init())
        #expect(sections == [.noBrews])
        #expect(CardDetailTab.brews.label(brewCount: 0) == "Brews")
        #expect(CardDetailTab.brews.label(brewCount: 4) == "Brews 4")
    }

    @Test func theCardOpensOnCoffeeUnlessABrewSentYou() throws {
        let detail = try String(contentsOf: DevBrief10.kohiRoot.appending(path: "Detail/CardDetailView.swift"))
        #expect(detail.contains("var startsOn: CardDetailTab = .coffee"))
        #expect(detail.contains("chosenTab ?? (startsAtSuggested ? .coffee : startsOn)"))
        // A saved brew moves to Brews; an abandoned one does not.
        #expect(detail.contains("guard live.brews.count > before else { return }"))
        #expect(detail.contains("pinnedViews: [.sectionHeaders]"))
        #expect(detail.contains("proxy.scrollTo(\"detail-rail\", anchor: .top)"))
    }

    @Test func theTopBarIsOnlyTheWayBack() throws {
        let detail = try String(contentsOf: DevBrief10.kohiRoot.appending(path: "Detail/CardDetailView.swift"))
        #expect(!detail.contains("showFaceMenu"))
        #expect(!detail.contains("confirmationDialog(Copy.cards"))
        #expect(detail.contains("onFlip: { looks.setOverride($0, for: live.id) }"))
        let strings = try String(contentsOf: DevBrief10.kohiRoot.appending(path: "App/Strings.swift"))
        #expect(!strings.contains("showTheScan"))
        #expect(!strings.contains("showTheKohiCard"))
        #expect(strings.contains("static let cards = \"Cards\""))
    }
}

struct TastingCaptureSortTests {
    private let roasters = ["Fève", "Belleville", "Coutume"]

    @Test func aCafeCardReadsAsOneCoffee() throws {
        let reading = TastingCapture.sort(try DevBrief10.fixture("kenya-tekangu-card"), roasters: roasters)
        guard case .fields(let parsed, let extra) = reading else {
            Issue.record("expected fields, got \(reading)")
            return
        }
        #expect(parsed.name == "Kenya Tekangu")
        #expect(parsed.country == "Kenya")
        #expect(parsed.process == "Washed")
        #expect(parsed.tastingNotes == ["Floral", "Red Currant", "Vanilla"])
        #expect(extra.isEmpty)
    }

    @Test func aMenuOfThreeAsksWhichOne() throws {
        let reading = TastingCapture.sort(try DevBrief10.fixture("menu-three"), roasters: roasters)
        guard case .menu(let candidates) = reading else {
            Issue.record("expected a menu, got \(reading)")
            return
        }
        #expect(candidates.map(\.name) == ["Ethiopia Guji", "Kenya Kiambu AA", "Colombia El Paraiso"])
        #expect(candidates.map(\.id) == [0, 1, 2])
    }

    @Test func aSlateWithOneCoffeeAlsoFillsMethodAndPrice() throws {
        let reading = TastingCapture.sort(try DevBrief10.fixture("slate-single"), roasters: roasters)
        guard case .fields(let parsed, let extra) = reading else {
            Issue.record("expected fields, got \(reading)")
            return
        }
        #expect(parsed.name == "Ethiopia Chelchele")
        #expect(extra.contains { $0.kind == .method && $0.value == "V60" })
        #expect(extra.contains { $0.kind == .price && $0.confidence == .read })

        var draft = TastingDraft()
        draft.fill(from: parsed)
        draft.fill(extra: extra)
        #expect(draft.method == .v60)
        #expect(draft.price != nil)
    }

    @Test func nothingReadableIsNothing() throws {
        #expect(TastingCapture.sort([String](), roasters: roasters) == .nothing)
        #expect(TastingCapture.sort(try DevBrief10.fixture("unreadable"), roasters: roasters) == .nothing)
    }

    @Test func aTypedNameIsNeverReplacedByTheRead() throws {
        var draft = TastingDraft()
        draft.coffee.name = "House filter"
        draft.method = .batch
        draft.priceText = "4"
        guard case .fields(let parsed, let extra) = TastingCapture.sort(try DevBrief10.fixture("slate-single"), roasters: roasters) else {
            Issue.record("expected fields")
            return
        }
        draft.fill(from: parsed)
        draft.fill(extra: extra)
        #expect(draft.coffee.name == "House filter")
        #expect(draft.method == .batch)
        #expect(draft.priceText == "4")
        #expect(draft.coffee.country == "Ethiopia")
    }

    @Test func oneScanReplacesBagAndMenu() throws {
        let compose = try String(contentsOf: DevBrief10.kohiRoot.appending(path: "Tastings/TastingComposeSheet.swift"))
        #expect(!compose.contains("TastingScanKind"))
        #expect(compose.contains("Copy.scanTheCard"))
        #expect(!compose.contains("Copy.scanBag"))
        #expect(Copy.toConfirm == "Read, to confirm")
    }
}

@MainActor
struct TastingFlowStepsTests {
    private static let crible = Place(name: "Crible", address: "75 Rue Buffon", latitude: 48.84, longitude: 2.36)

    @Test func sixStepsOrFiveWhenThePlaceIsKnown() {
        let full = TastingFlowSteps(placeKnown: false)
        #expect(full.total == 6)
        #expect(full.current == .place)
        #expect(full.steps == [.place, .source, .coffee, .made, .rating, .remember])

        let known = TastingFlowSteps(placeKnown: true)
        #expect(known.total == 5)
        #expect(known.current == .source)
        #expect(!known.steps.contains(.place))
    }

    @Test func aScanFromHomeStartsOnWhichCoffee() {
        let steps = TastingFlowSteps(placeKnown: true, startingAt: .coffee)
        #expect(steps.current == .coffee)
        #expect(steps.index == 1)
    }

    @Test func backAndNextStayInsideTheFlow() {
        var steps = TastingFlowSteps(placeKnown: false)
        let wentBackFromFirst = steps.back()
        #expect(!wentBackFromFirst)
        for _ in 0..<10 { steps.next() }
        #expect(steps.current == .remember)
        #expect(steps.isLast)
        let wentBack = steps.back()
        #expect(wentBack)
        #expect(steps.current == .rating)
    }

    @Test func saveNowOnlyOnTheBonusStepsOnceSavable() {
        var steps = TastingFlowSteps(placeKnown: false)
        var offered: [TastingStep] = []
        for _ in 0..<steps.total {
            if steps.offersSaveNow(canSave: true) { offered.append(steps.current) }
            #expect(!steps.offersSaveNow(canSave: false))
            steps.next()
        }
        #expect(offered == [.made, .rating])
    }

    @Test func anAutomaticPlaceAloneIsNothingToDiscard() {
        var draft = TastingDraft()
        #expect(!draft.hasContent)
        draft.autofill(Self.crible, "crible")
        #expect(!draft.hasContent)
        draft.coffee.name = "Chelbesa"
        #expect(draft.hasContent)

        let flow = try? String(contentsOf: DevBrief10.kohiRoot.appending(path: "Tastings/TastingFlow.swift"))
        #expect(flow?.contains("confirmationDialog(Copy.discardTasting") == true)
        #expect(flow?.contains("if draft.hasContent {") == true)
    }

    @Test func savingWritesTheTastingToTheStore() {
        let name = UUID().uuidString
        let tastings = TastingStore(
            files: JSONFileStore(filename: "tastings-flow-\(name).json"),
            ledgerFile: JSONDocumentStore(filename: "tastings-ledger-flow-\(name).json")
        )
        let roasters = RoasterStore(
            files: JSONFileStore(filename: "roasters-flow-\(name).json"),
            seedStamp: JSONDocumentStore(filename: "roaster-stamp-flow-\(name).json")
        )
        let places = PlaceIndex(places: [], notes: JSONDocumentStore(filename: "place-notes-flow-\(name).json"))

        var draft = TastingDraft()
        draft.choose(Self.crible, "crible")
        draft.coffee.name = "Chelbesa"
        draft.rating = 4
        #expect(draft.canSave)

        let saved = TastingSaver.save(draft, editing: nil, tastings: tastings, roasters: roasters, places: places)
        #expect(tastings.tastings.map(\.id) == [saved.id])
        #expect(saved.coffee.name == "Chelbesa")
        #expect(saved.rating == 4)
    }

    @Test func newTastingsOpenTheFlowAndEditingKeepsTheSheet() throws {
        let grid = try String(contentsOf: DevBrief10.kohiRoot.appending(path: "Grid/GridScreen.swift"))
        #expect(grid.contains("TastingFlow(onSaved: { _ in showTastings() })"))
        #expect(!grid.contains("TastingComposeSheet()"))
        let detail = try String(contentsOf: DevBrief10.kohiRoot.appending(path: "Tastings/TastingDetailView.swift"))
        #expect(detail.contains("TastingComposeSheet(editing:"))
    }
}

struct ScanIntentTests {
    private static let now = Date(timeIntervalSince1970: 1_790_000_000)
    /// About 1.11 m of latitude.
    private static let metre = 1.0 / 111_000

    private static func fix(accuracy: Double = 20, age: TimeInterval = 30) -> Fix {
        Fix(latitude: 48.8634, longitude: 2.3488, accuracy: accuracy, at: now.addingTimeInterval(-age))
    }

    private static func place(_ name: String, metresNorth: Double) -> Place {
        Place(name: name, address: "", latitude: 48.8634 + metresNorth * metre, longitude: 2.3488)
    }

    private static func suggestion(_ name: String, metres: Double, _ source: PlaceSuggestion.Source) -> PlaceSuggestion {
        PlaceSuggestion(place: place(name, metresNorth: metres), placeID: name, source: source)
    }

    private static func decide(
        fix: Fix? = fix(),
        yours: [PlaceSuggestion] = [],
        seeds: [PlaceSuggestion] = [],
        maps: [Place] = [],
        spots: [ScanSpot] = []
    ) -> ScanIntent {
        ScanIntent.decide(fix: fix, yours: yours, seeds: seeds, maps: maps, spots: spots, now: now)
    }

    @Test func aPreciseFixAtYourCafeAsks() {
        let yours = Self.suggestion("Galata", metres: 50, .yours)
        #expect(Self.decide(yours: [yours]) == .ask(yours))
    }

    @Test func noFixOrAWeakOneIsABag() {
        let yours = [Self.suggestion("Galata", metres: 20, .yours)]
        #expect(Self.decide(fix: nil, yours: yours) == .bag)
        #expect(Self.decide(fix: Self.fix(accuracy: 80), yours: yours) == .bag)
        #expect(Self.decide(fix: Self.fix(accuracy: 65), yours: yours) != .bag)
        #expect(Self.decide(fix: Self.fix(age: 6 * 60), yours: yours) == .bag)
    }

    @Test func eachSourceHasItsOwnRadius() {
        #expect(Self.decide(yours: [Self.suggestion("Galata", metres: 90, .yours)]) == .bag)
        let seed = Self.suggestion("Crible", metres: 70, .seed)
        #expect(Self.decide(seeds: [seed]) == .ask(seed))
        #expect(Self.decide(maps: [Self.place("Bistrot", metresNorth: 60)]) == .bag)
        guard case .ask(let hit) = Self.decide(maps: [Self.place("Café", metresNorth: 30)]) else {
            Issue.record("a Maps café at 30 m should ask")
            return
        }
        #expect(hit.place.name == "Café")
        #expect(hit.source == .maps)
    }

    @Test func yoursBeatsACloserMapsCafeAndTheNearestWinsWithin() {
        let yours = Self.suggestion("Galata", metres: 70, .yours)
        let decided = Self.decide(yours: [yours], maps: [Self.place("Café", metresNorth: 5)])
        #expect(decided == .ask(yours))

        let near = Self.suggestion("Near", metres: 10, .seed)
        let far = Self.suggestion("Far", metres: 60, .seed)
        #expect(Self.decide(seeds: [far, near]) == .ask(near))
    }

    @Test func aPlaceWithoutCoordinatesNeverAsks() {
        let unresolved = PlaceSuggestion(
            place: Place(name: "Somewhere", address: "", latitude: 0, longitude: 0),
            placeID: "x",
            source: .seed
        )
        #expect(Self.decide(seeds: [unresolved]) == .bag)
    }

    @Test func twoBagsInARowSilenceTheSpotAndACupResetsIt() {
        let yours = [Self.suggestion("Home café", metres: 10, .yours)]
        let fix = Self.fix()
        var spots = ScanSpots.recording(.bag, at: fix, in: [], now: Self.now)
        #expect(Self.decide(yours: yours, spots: spots) != .bag)
        spots = ScanSpots.recording(.bag, at: fix, in: spots, now: Self.now)
        #expect(Self.decide(yours: yours, spots: spots) == .bag)
        spots = ScanSpots.recording(.cup, at: fix, in: spots, now: Self.now)
        #expect(Self.decide(yours: yours, spots: spots) != .bag)
        #expect(spots.count == 1)
    }

    @Test func atMostTwentySpotsAndTheOldestLeave() {
        var spots: [ScanSpot] = []
        for step in 0..<25 {
            let fix = Fix(latitude: 48.8 + Double(step) * 0.01, longitude: 2.3, accuracy: 10, at: Self.now)
            spots = ScanSpots.recording(.bag, at: fix, in: spots, now: Self.now.addingTimeInterval(Double(step)))
        }
        #expect(spots.count == ScanSpots.limit)
        #expect(!spots.contains { $0.latitude == ScanSpot.rounded(48.8) })
    }

    @Test func spotsLiveInUserDefaultsAndClear() throws {
        let defaults = try #require(UserDefaults(suiteName: "scan-spots-\(UUID().uuidString)"))
        ScanSpots.record(.bag, at: Self.fix(), now: Self.now, in: defaults)
        #expect(ScanSpots.load(from: defaults).count == 1)
        #expect(defaults.data(forKey: "scan.spots") != nil)
        ScanSpots.clear(defaults)
        #expect(ScanSpots.load(from: defaults).isEmpty)
    }

    @Test func nothingHereTouchesTheNetworkOrTheSync() throws {
        let intent = try String(contentsOf: DevBrief10.kohiRoot.appending(path: "Process/ScanIntent.swift"))
        for word in ["URLSession", "Supabase", "SyncOutbox", "sink"] {
            #expect(!intent.contains(word))
        }
        let sheet = try String(contentsOf: DevBrief10.kohiRoot.appending(path: "Grid/ScanIntentSheet.swift"))
        #expect(!sheet.contains("URLSession"))
    }
}

@MainActor
struct HomeFixTests {
    final class FakeSource: FixSource {
        var fix: Fix?
        var starts = 0
        init(fix: Fix? = nil) { self.fix = fix }
        func start() { starts += 1 }
    }

    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func withoutPermissionTheHomeNeverStartsTheLocator() {
        let source = FakeSource()
        #expect(!HomeFix.refresh(source, isAuthorized: false, now: now))
        #expect(source.starts == 0)
    }

    @Test func aFreshFixIsKeptAndAStaleOneRetaken() {
        let fresh = FakeSource(fix: Fix(latitude: 48.86, longitude: 2.35, accuracy: 10, at: now.addingTimeInterval(-60)))
        #expect(!HomeFix.refresh(fresh, isAuthorized: true, now: now))
        #expect(fresh.starts == 0)

        let stale = FakeSource(fix: Fix(latitude: 48.86, longitude: 2.35, accuracy: 10, at: now.addingTimeInterval(-6 * 60)))
        #expect(HomeFix.refresh(stale, isAuthorized: true, now: now))
        #expect(stale.starts == 1)

        let none = FakeSource()
        #expect(HomeFix.refresh(none, isAuthorized: true, now: now))
        #expect(none.starts == 1)
    }

    @Test func theHomeAsksOnlyThroughTheGuard() throws {
        let grid = try String(contentsOf: DevBrief10.kohiRoot.appending(path: "Grid/GridScreen.swift"))
        #expect(grid.contains("HomeFix.refresh(nearby.locator, isAuthorized: PlaceLocator.isAuthorized)"))
        #expect(!grid.contains("nearby.start()"))
        #expect(!grid.contains("requestWhenInUseAuthorization"))
    }
}

/// The three drawn demos, read the way a photo of them would be.
@MainActor
struct DemoScanOCRTests {
    private let roasters = ["Fève", "Belleville", "Hexagone"]

    private func lines(_ demo: DemoScan) async throws -> [TextExtractor.Line] {
        let image = try #require(demo.image())
        return await TextExtractor.read(image: image)
    }

    @Test func theBagReadsAsACoffeeForTheCollection() async throws {
        let lines = try await lines(.bag)
        let parsed = FieldParser.parse(lines)
        #expect(parsed.name?.contains("Chelchele") == true)
        #expect(parsed.country == "Ethiopia")
        #expect(parsed.process == "Washed")
    }

    @Test func theCafeCardReadsAsOneCoffee() async throws {
        let reading = TastingCapture.sort(try await lines(.card), roasters: roasters)
        guard case .fields(let parsed, let extra) = reading else {
            Issue.record("expected fields, got \(reading)")
            return
        }
        #expect(parsed.name == "Kenya Tekangu")
        #expect(parsed.country == "Kenya")
        #expect(extra.contains { $0.kind == .method && $0.value == "V60" })
    }

    @Test func theMenuAsksWhichOfThree() async throws {
        let reading = TastingCapture.sort(try await lines(.menu), roasters: roasters)
        guard case .menu(let candidates) = reading else {
            Issue.record("expected a menu, got \(reading)")
            return
        }
        #expect(candidates.map(\.name) == ["Ethiopia Guji", "Kenya Kiambu AA", "Colombia El Paraiso"])
    }

    @Test func aScannedCardIsKeptAmongTheTastingPhotos() async throws {
        let captured = try #require(DemoScan.card.capture())
        let scan = ScanResult(image: captured.image, quad: try #require(captured.quad), enhance: false)
        var draft = TastingDraft()
        let binding = Binding(get: { draft }, set: { draft = $0 })
        let flags = AIFlags(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
        flags.setOn(.cardVision, false)
        flags.setOn(.menuExtract, false)
        await TastingReader().read(scan, into: binding, roasters: roasters, cards: [], flags: flags, events: AIEventLog())
        #expect(draft.photos.count == 1)
        let name = try #require(draft.photos.first)
        #expect(TastingPhotos.exists(tastingID: draft.id, name: name))
        #expect(draft.coffee.name == "Kenya Tekangu")
        try? FileManager.default.removeItem(at: TastingPhotos.directory(for: draft.id))
    }

    @Test func demosLiveOnlyInDebugBuilds() throws {
        let demo = try String(contentsOf: DevBrief10.kohiRoot.appending(path: "Scan/DemoScan.swift"))
        #expect(demo.hasPrefix("#if DEBUG"))
        let camera = try String(contentsOf: DevBrief10.kohiRoot.appending(path: "Scan/CameraCaptureSource.swift"))
        #expect(camera.contains("#if DEBUG\n    private var sampleDemoButton"))
        let screen = try String(contentsOf: DevBrief10.kohiRoot.appending(path: "Scan/ScanScreen.swift"))
        #expect(screen.contains("#if targetEnvironment(simulator) && DEBUG"))
    }

    @Test func eachDemoLandsOnTheSampleSurface() throws {
        for demo in DemoScan.allCases {
            let captured = try #require(demo.capture())
            #expect(captured.image.width == 2400)
        }
    }
}

enum DevBrief10 {
    static var kohiRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Kohi")
    }

    static func fixture(_ name: String) throws -> [String] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "Fixtures/tasting/\(name).txt")
        return try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
    }
}
