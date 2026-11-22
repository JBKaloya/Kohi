import Foundation

nonisolated enum RoastBand: String, CaseIterable, Identifiable, Sendable {
    case light
    case medium
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .light: "Light"
        case .medium: "Medium"
        case .dark: "Dark"
        }
    }

    func matches(_ level: RoastLevel?) -> Bool {
        switch self {
        case .light: level == .superLight || level == .light || level == .mediumLight
        case .medium: level == .medium
        case .dark: level == .mediumDark || level == .dark
        }
    }
}

/// Where a recipe sits: saved by you, or in the catalogue. The tabs, once a
/// filter is on.
nonisolated enum RecipeOrigin: String, CaseIterable, Identifiable, Sendable {
    case mine
    case reference

    var id: String { rawValue }

    var label: String {
        switch self {
        case .mine: "Mine"
        case .reference: Copy.fromThePros
        }
    }
}

nonisolated enum RecipeProfileTag: String, CaseIterable, Identifiable, Sendable {
    case fruity, floral, sweet, bright, clean, body

    var id: String { rawValue }

    var label: String { rawValue.capitalized }
}

nonisolated enum DripperChip: String, CaseIterable, Identifiable, Sendable {
    case v60, flat, chemex, aeropress, immersion, espresso

    var id: String { rawValue }

    var label: String {
        switch self {
        case .v60: "V60"
        case .flat: "Flat"
        case .chemex: "Chemex"
        case .aeropress: "AeroPress"
        case .immersion: "Immersion"
        case .espresso: "Espresso"
        }
    }

    var method: BrewMethod {
        switch self {
        case .v60: .v60
        case .flat: .filter
        case .chemex: .filter
        case .aeropress: .aeropress
        case .immersion: .frenchPress
        case .espresso: .espresso
        }
    }
}

/// The recipe filters read off the facets, one value each.
nonisolated struct RecipeFilterState: Equatable, Sendable {
    var dripper: DripperChip?
    var size: RecipeSize = .cup
    var roast: RoastBand?
    var origin: RecipeOrigin?
    var profile: RecipeProfileTag?
    var authorGrinder: String?

    var method: BrewMethod? { dripper?.method }

    init() {}

    init(_ active: ActiveFilters) {
        dripper = active.value(of: RecipeFilters.dripper).flatMap(DripperChip.init(rawValue:))
        size = active.value(of: RecipeFilters.cup).flatMap(RecipeSize.init(rawValue:)) ?? .cup
        roast = active.value(of: RecipeFilters.roast).flatMap(RoastBand.init(rawValue:))
        origin = active.value(of: RecipeFilters.source).flatMap(RecipeOrigin.init(rawValue:))
        profile = active.value(of: RecipeFilters.profile).flatMap(RecipeProfileTag.init(rawValue:))
        authorGrinder = active.value(of: RecipeFilters.grinder)
    }

    var isActive: Bool {
        dripper != nil || size != .cup || roast != nil || origin != nil || profile != nil || authorGrinder != nil
    }

    /// One rule for every recipe, wherever it comes from.
    func matches(_ recipe: Recipe, origin recipeOrigin: RecipeOrigin) -> Bool {
        if let origin, origin != recipeOrigin { return false }
        if let method, recipe.method != method { return false }
        if let roast,
           !recipe.notes.localizedCaseInsensitiveContains(roast.label),
           !recipe.name.localizedCaseInsensitiveContains(roast.label) { return false }
        if let profile, !recipe.profileTags.contains(profile.rawValue) { return false }
        if let authorGrinder, recipe.authorGrinder != authorGrinder { return false }
        return true
    }
}

/// Narrowing the recipes. With a filter on, Mine and From the pros are one
/// list, and the tab they came from is the Source facet.
nonisolated enum RecipeFilters {
    static let source = "source"
    static let dripper = "dripper"
    static let cup = "cup"
    static let roast = "roast"
    static let grinder = "grinder"
    static let profile = "profile"

    static func facets(grinders: [String]) -> [FilterFacet] {
        var facets = [
            FilterFacet(id: source, label: Copy.filterSource, options: options(RecipeOrigin.allCases, \.label)),
            FilterFacet(id: dripper, label: Copy.filterDripper, options: options(DripperChip.allCases, \.label)),
            // One cup is what every recipe already reads as: not a filter.
            FilterFacet(id: cup, label: Copy.filterCup, options: options(RecipeSize.allCases.filter { $0 != .cup }, \.label)),
            FilterFacet(id: roast, label: Copy.filterRoast, options: options(RoastBand.allCases, \.label)),
        ]
        if !grinders.isEmpty {
            facets.append(FilterFacet(
                id: grinder,
                label: Copy.filterGrinder,
                options: grinders.map { FilterOption(id: $0, label: $0) }
            ))
        }
        facets.append(FilterFacet(id: profile, label: Copy.filterProfile, options: options(RecipeProfileTag.allCases, \.label)))
        return facets
    }

    struct Match: Identifiable {
        let recipe: Recipe
        let origin: RecipeOrigin
        var id: String { origin.rawValue + recipe.id.uuidString }
    }

    /// Mine first, then the catalogue, each kept when it passes the filters.
    static func recipes(mine: [Recipe], references: [Recipe], state: RecipeFilterState) -> [Match] {
        mine.filter { state.matches($0, origin: .mine) }.map { Match(recipe: $0, origin: .mine) }
            + references.filter { state.matches($0, origin: .reference) }.map { Match(recipe: $0, origin: .reference) }
    }

    private static func options<Item: RawRepresentable>(_ items: [Item], _ label: (Item) -> String) -> [FilterOption]
        where Item.RawValue == String {
        items.map { FilterOption(id: $0.rawValue, label: label($0)) }
    }
}
