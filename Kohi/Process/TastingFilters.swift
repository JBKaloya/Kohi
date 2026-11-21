import Foundation

nonisolated enum TastingPeriod: String, CaseIterable, Sendable {
    case thisMonth
    case threeMonths
    case thisYear

    var label: String {
        switch self {
        case .thisMonth: "This month"
        case .threeMonths: "Last 3 months"
        case .thisYear: "This year"
        }
    }

    func contains(_ date: Date, now: Date, calendar: Calendar) -> Bool {
        switch self {
        case .thisMonth:
            calendar.isDate(date, equalTo: now, toGranularity: .month)
        case .threeMonths:
            calendar.date(byAdding: .month, value: -3, to: now).map { date >= $0 && date <= now } ?? false
        case .thisYear:
            calendar.isDate(date, equalTo: now, toGranularity: .year)
        }
    }
}

nonisolated enum TastingScoreFloor: String, CaseIterable, Sendable {
    case fourAndUp
    case five

    var label: String {
        switch self {
        case .fourAndUp: "4★ and up"
        case .five: "5★"
        }
    }

    func matches(_ halves: Int?) -> Bool {
        guard let halves else { return false }
        switch self {
        case .fourAndUp: return halves >= 8
        case .five: return halves == 10
        }
    }
}

/// Narrowing the tastings: when, whose coffee, where, how good. Over every
/// tasting, whichever rail was open.
nonisolated enum TastingFilters {
    static let period = "period"
    static let roaster = "roaster"
    static let place = "place"
    static let score = "score"

    static func facets(for tastings: [Tasting]) -> [FilterFacet] {
        var facets = [FilterFacet(
            id: period,
            label: "Period",
            options: TastingPeriod.allCases.map { FilterOption(id: $0.rawValue, label: $0.label) }
        )]
        let roasters = distinct(tastings.map(\.coffee.roaster))
        if !roasters.isEmpty {
            facets.append(FilterFacet(id: roaster, label: "Roaster", options: roasters, allowsMany: true))
        }
        let places = distinct(tastings.compactMap { $0.place?.name })
        if !places.isEmpty {
            facets.append(FilterFacet(id: place, label: "Place", options: places, allowsMany: true))
        }
        facets.append(FilterFacet(
            id: score,
            label: "Rating",
            options: TastingScoreFloor.allCases.map { FilterOption(id: $0.rawValue, label: $0.label) }
        ))
        return facets
    }

    static func apply(
        _ tastings: [Tasting],
        _ active: ActiveFilters,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [Tasting] {
        let period = active.value(of: period).flatMap(TastingPeriod.init(rawValue:))
        let roasters = Set(active.values(of: roaster))
        let places = Set(active.values(of: place))
        let floor = active.value(of: score).flatMap(TastingScoreFloor.init(rawValue:))
        return tastings.filter { tasting in
            if let period, !period.contains(tasting.date, now: now, calendar: calendar) { return false }
            if !roasters.isEmpty, !roasters.contains(key(tasting.coffee.roaster)) { return false }
            if !places.isEmpty, !places.contains(key(tasting.place?.name ?? "")) { return false }
            if let floor, !floor.matches(tasting.ratingHalves) { return false }
            return true
        }
    }

    /// One option per name, spelled as it was first met, sorted.
    private static func distinct(_ names: [String]) -> [FilterOption] {
        var seen: [String: String] = [:]
        for name in names {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            let id = key(trimmed)
            guard !id.isEmpty, seen[id] == nil else { continue }
            seen[id] = trimmed
        }
        return seen.map { FilterOption(id: $0.key, label: $0.value) }
            .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    private static func key(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespaces).lowercased()
    }
}
