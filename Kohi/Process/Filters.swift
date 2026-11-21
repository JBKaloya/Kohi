import Foundation

/// One value a list can be narrowed to: "Glitch", "4★ and up".
nonisolated struct FilterOption: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
}

/// One criterion and its values. A facet that allows many keeps every value
/// picked; the others hold one, and a new pick replaces it.
nonisolated struct FilterFacet: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let options: [FilterOption]
    var allowsMany = false
}

/// What is narrowing a list right now, facet by facet, in pick order.
/// Empty is the list as it comes, and the tabs.
nonisolated struct ActiveFilters: Equatable, Sendable {
    struct Chip: Identifiable, Equatable, Sendable {
        let facetID: String
        let option: FilterOption
        var id: String { facetID + "\u{1f}" + option.id }
    }

    private(set) var chosen: [String: [String]] = [:]

    var isEmpty: Bool { chosen.values.allSatisfy(\.isEmpty) }

    func values(of facetID: String) -> [String] { chosen[facetID] ?? [] }

    func value(of facetID: String) -> String? { values(of: facetID).first }

    func contains(_ optionID: String, in facetID: String) -> Bool {
        values(of: facetID).contains(optionID)
    }

    mutating func toggle(_ optionID: String, in facet: FilterFacet) {
        var current = values(of: facet.id)
        if let index = current.firstIndex(of: optionID) {
            current.remove(at: index)
        } else if facet.allowsMany {
            current.append(optionID)
        } else {
            current = [optionID]
        }
        chosen[facet.id] = current.isEmpty ? nil : current
    }

    mutating func remove(_ optionID: String, from facetID: String) {
        let rest = values(of: facetID).filter { $0 != optionID }
        chosen[facetID] = rest.isEmpty ? nil : rest
    }

    mutating func removeAll() { chosen = [:] }

    /// The removable chips that stand in for the tabs, in facet order.
    func chips(in facets: [FilterFacet]) -> [Chip] {
        facets.flatMap { facet in
            values(of: facet.id).compactMap { id in
                facet.options.first { $0.id == id }.map { Chip(facetID: facet.id, option: $0) }
            }
        }
    }

    /// The pill is the result: the criterion's name while nothing is picked,
    /// then the values picked.
    func title(of facet: FilterFacet) -> String {
        let labels = values(of: facet.id).compactMap { id in facet.options.first { $0.id == id }?.label }
        return labels.isEmpty ? facet.label : labels.joined(separator: ", ")
    }
}
