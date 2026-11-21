import SwiftUI
import Testing
@testable import Kohi

/// 21 November: one filter component for Tastings and Brews. The pill is the
/// result, and an active filter takes the place of the tabs.
struct ActiveFiltersTests {
    static let roaster = FilterFacet(
        id: "roaster",
        label: "Roaster",
        options: [
            FilterOption(id: "glitch", label: "Glitch"),
            FilterOption(id: "onibus", label: "Onibus"),
            FilterOption(id: "leaves", label: "Leaves"),
        ],
        allowsMany: true
    )
    static let score = FilterFacet(
        id: "score",
        label: "Rating",
        options: [FilterOption(id: "four", label: "4★ and up"), FilterOption(id: "five", label: "5★")]
    )

    @Test func thePillNamesTheCriterionThenShowsTheValues() {
        var active = ActiveFilters()
        #expect(active.title(of: Self.roaster) == "Roaster")
        active.toggle("glitch", in: Self.roaster)
        active.toggle("onibus", in: Self.roaster)
        #expect(active.title(of: Self.roaster) == "Glitch, Onibus")
        #expect(FilterPicker.truncated("Glitch, Onibus, Leaves, Fuglen") == "Glitch, Onibus…")
        #expect(FilterPicker.truncated("Glitch") == "Glitch")
    }

    @Test func aSingleFacetKeepsOneValue() {
        var active = ActiveFilters()
        active.toggle("four", in: Self.score)
        active.toggle("five", in: Self.score)
        #expect(active.values(of: "score") == ["five"])
        active.toggle("five", in: Self.score)
        #expect(active.isEmpty)
    }

    @Test func takingOutTheLastChipBringsTheTabsBack() {
        var active = ActiveFilters()
        #expect(active.isEmpty)
        active.toggle("glitch", in: Self.roaster)
        active.toggle("four", in: Self.score)
        let chips = active.chips(in: [Self.roaster, Self.score])
        #expect(chips.map(\.option.label) == ["Glitch", "4★ and up"])
        active.remove("glitch", from: "roaster")
        #expect(!active.isEmpty)
        active.remove("four", from: "score")
        #expect(active.isEmpty)
    }

    @Test func theScreensKeepTheirTabWhileFiltered() throws {
        for path in ["Tastings/TastingsScreen.swift", "Recipes/RecipesScreen.swift"] {
            let source = try String(contentsOf: DevBrief10.kohiRoot.appending(path: path), encoding: .utf8)
            #expect(source.contains("FilterBar(facets:"), "\(path)")
            #expect(source.contains("@State private var filters = ActiveFilters()"), "\(path)")
        }
        let recipes = try String(
            contentsOf: DevBrief10.kohiRoot.appending(path: "Recipes/RecipesScreen.swift"),
            encoding: .utf8
        )
        #expect(!recipes.contains("RecipeFilterSheet"))
        #expect(!recipes.contains("currentFilter.summary"))
        #expect(recipes.contains("recipes.tab"))
    }

    @Test func unfoldIsASpringOfItsOwn() throws {
        let motion = try String(
            contentsOf: DevBrief10.kohiRoot.appending(path: "Motion/Motion.swift"),
            encoding: .utf8
        )
        #expect(motion.contains("static let unfold = Animation.spring(response: 0.38, dampingFraction: 0.63)"))
        let picker = try String(
            contentsOf: DevBrief10.kohiRoot.appending(path: "Design/FilterPicker.swift"),
            encoding: .utf8
        )
        #expect(!picker.contains("Animation.spring"))
        #expect(!picker.contains("\"checkmark"))
    }
}

struct TastingFiltersTests {
    static let now = Date(timeIntervalSince1970: 1_795_000_000)
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    static func tasting(roaster: String, place: String?, halves: Int?, daysAgo: Int) -> Tasting {
        var tasting = Tasting(
            date: calendar.date(byAdding: .day, value: -daysAgo, to: now)!,
            context: place.map { .out(place: Place(name: $0, address: "", latitude: 0, longitude: 0), placeID: nil) }
                ?? .home(brewID: nil),
            ratingHalves: halves
        )
        tasting.coffee.roaster = roaster
        return tasting
    }

    static let all = [
        tasting(roaster: "Glitch", place: "Glitch Ginza", halves: 10, daysAgo: 0),
        tasting(roaster: "Onibus", place: "Onibus Nakameguro", halves: 7, daysAgo: 40),
        tasting(roaster: "glitch ", place: "Glitch Ginza", halves: 8, daysAgo: 200),
        tasting(roaster: "Leaves", place: nil, halves: nil, daysAgo: 1),
    ]

    @Test func theFacetsComeFromTheTastings() {
        let facets = TastingFilters.facets(for: Self.all)
        #expect(facets.map(\.id) == ["period", "roaster", "place", "score"])
        let roasters = facets.first { $0.id == "roaster" }!.options.map(\.label)
        #expect(roasters == ["Glitch", "Leaves", "Onibus"])
        #expect(facets.first { $0.id == "place" }!.options.count == 2)
    }

    @Test func eachFacetNarrowsAndTheyAddUp() {
        let facets = TastingFilters.facets(for: Self.all)
        func facet(_ id: String) -> FilterFacet { facets.first { $0.id == id }! }
        var active = ActiveFilters()

        active.toggle(TastingScoreFloor.fourAndUp.rawValue, in: facet("score"))
        #expect(TastingFilters.apply(Self.all, active, now: Self.now, calendar: Self.calendar).count == 2)

        active.toggle(TastingPeriod.threeMonths.rawValue, in: facet("period"))
        let recent = TastingFilters.apply(Self.all, active, now: Self.now, calendar: Self.calendar)
        #expect(recent.map(\.ratingHalves) == [10])

        var byRoaster = ActiveFilters()
        byRoaster.toggle("glitch", in: facet("roaster"))
        byRoaster.toggle("onibus", in: facet("roaster"))
        #expect(TastingFilters.apply(Self.all, byRoaster, now: Self.now, calendar: Self.calendar).count == 3)

        var five = ActiveFilters()
        five.toggle(TastingScoreFloor.five.rawValue, in: facet("score"))
        #expect(TastingFilters.apply(Self.all, five, now: Self.now, calendar: Self.calendar).count == 1)
    }
}

struct RecipeFiltersTests {
    static let mine = [
        Recipe(name: "My V60", method: .v60, dose: 15, water: 250),
        Recipe(name: "My AeroPress", method: .aeropress, dose: 15, water: 220),
    ]
    static let pros = [
        Recipe(name: "Ultimate V60", method: .v60, dose: 30, water: 500, source: .reference, profileTags: ["fruity"]),
        Recipe(name: "Press", method: .frenchPress, dose: 30, water: 500, source: .reference),
    ]

    @Test func aFilterOnMakesOneListOfMineAndThePros() {
        var active = ActiveFilters()
        let facets = RecipeFilters.facets(grinders: [])
        let dripper = facets.first { $0.id == RecipeFilters.dripper }!
        active.toggle(DripperChip.v60.rawValue, in: dripper)
        let state = RecipeFilterState(active)
        #expect(state.isActive)
        let matches = RecipeFilters.recipes(mine: Self.mine, references: Self.pros, state: state)
        #expect(matches.map(\.recipe.name) == ["My V60", "Ultimate V60"])
        #expect(matches.map(\.origin) == [.mine, .reference])
    }

    @Test func sourceIsTheOldTab() {
        var active = ActiveFilters()
        let source = RecipeFilters.facets(grinders: []).first { $0.id == RecipeFilters.source }!
        #expect(source.options.map(\.label) == ["Mine", Copy.fromThePros])
        active.toggle(RecipeOrigin.reference.rawValue, in: source)
        let matches = RecipeFilters.recipes(mine: Self.mine, references: Self.pros, state: RecipeFilterState(active))
        #expect(matches.allSatisfy { $0.origin == .reference })
        #expect(matches.count == 2)
    }

    @Test func theSheetsCriteriaAllMoved() {
        let ids = RecipeFilters.facets(grinders: ["Comandante C40"]).map(\.id)
        #expect(ids == ["source", "dripper", "cup", "roast", "grinder", "profile"])
        #expect(!RecipeFilters.facets(grinders: []).map(\.id).contains("grinder"))
        let cup = RecipeFilters.facets(grinders: []).first { $0.id == RecipeFilters.cup }!
        #expect(!cup.options.map(\.id).contains(RecipeSize.cup.rawValue))
    }

    @Test func profileNarrowsEveryRecipeAlike() {
        var active = ActiveFilters()
        let profile = RecipeFilters.facets(grinders: []).first { $0.id == RecipeFilters.profile }!
        active.toggle(RecipeProfileTag.fruity.rawValue, in: profile)
        let matches = RecipeFilters.recipes(mine: Self.mine, references: Self.pros, state: RecipeFilterState(active))
        #expect(matches.map(\.recipe.name) == ["Ultimate V60"])
    }

    @Test func noFilterIsNotActive() {
        #expect(!RecipeFilterState(ActiveFilters()).isActive)
    }
}

@Suite(.serialized)
@MainActor
struct FilterPickerSnapshotTests {
    static let roaster = ActiveFiltersTests.roaster

    @Test func closedPill() {
        SnapshotSupport.image(
            of: FilterPicker(facet: Self.roaster, active: .constant(ActiveFilters()), isOpen: false) {}
                .padding(26),
            width: 240,
            height: 90,
            named: "closed"
        )
    }

    @Test func openList() {
        var active = ActiveFilters()
        active.toggle("onibus", in: Self.roaster)
        SnapshotSupport.image(
            of: VStack(alignment: .leading, spacing: 6) {
                FilterPicker(facet: Self.roaster, active: .constant(active), isOpen: false) {}
                FilterOptionList(facet: Self.roaster, active: .constant(active), cascades: false)
                    .fixedSize()
            }
            .padding(26),
            width: 280,
            height: 240,
            named: "open"
        )
    }

    @Test func threeValuesInThePillAndAsChips() {
        var active = ActiveFilters()
        for id in ["glitch", "onibus", "leaves"] { active.toggle(id, in: Self.roaster) }
        SnapshotSupport.image(
            of: FilterBar(facets: [Self.roaster], active: .constant(active)) {
                Text("Tabs")
            }
            .padding(26),
            height: 120,
            named: "three"
        )
    }
}
