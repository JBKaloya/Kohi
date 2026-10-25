import Foundation

/// Shared cupboard resolution for With what, Today's settings, and prefill.
/// A brewer here is a dripper **or** an espresso machine.
@MainActor
enum BrewKit {
    static let journeyTabs: [BrewerFamily] = [.pourOver, .immersion, .espresso]

    static func isCupboard(_ kind: EquipmentKind) -> Bool {
        kind == .brewer || kind == .espressoMachine
    }

    static func activeBrewer(on brew: Brew, in setup: SetupStore) -> Equipment? {
        brew.equipmentIDs.compactMap { setup.equipment(id: $0) }
            .first { isCupboard($0.kind) }
    }

    /// Each family matches only itself — no absorption rules.
    static func matches(_ family: BrewerFamily, _ itemFamily: BrewerFamily?) -> Bool {
        let resolved = itemFamily ?? .pourOver
        return resolved == family
    }

    static func matches(_ family: BrewerFamily, _ item: Equipment) -> Bool {
        if item.kind == .espressoMachine { return family == .espresso }
        if let itemFamily = item.family {
            return matches(family, itemFamily)
        }
        if let inferred = inferredType(for: item) {
            return matches(family, inferred.family)
        }
        return family == .pourOver
    }

    /// Method a cupboard item should write, even when `brewerType` was never stored.
    static func method(for item: Equipment) -> BrewMethod? {
        if item.kind == .espressoMachine { return .espresso }
        return inferredType(for: item)?.method
    }

    static func inferredType(for item: Equipment) -> BrewerType? {
        if item.kind == .espressoMachine { return .espresso }
        return item.brewerKind
            ?? BrewerType.parse(item.model)
            ?? BrewerType.parse(item.brand)
            ?? BrewerType.parse(item.displayName)
    }

    static func fallbackMethod(_ family: BrewerFamily) -> BrewMethod {
        switch family {
        case .pourOver: .v60
        case .immersion: .frenchPress
        case .espresso: .espresso
        }
    }

    static func tab(for method: BrewMethod?) -> BrewerFamily {
        method?.journeyTab ?? .pourOver
    }

    static func clearCupboard(from brew: inout Brew, setup: SetupStore) {
        brew.equipmentIDs.removeAll { id in
            guard let kind = setup.equipment(id: id)?.kind else { return false }
            return isCupboard(kind)
        }
    }

    /// Switch Filter / Espresso: drop the other family's dripper, never leave a V60 on espresso.
    static func applyFamily(
        _ family: BrewerFamily,
        to brew: inout Brew,
        setup: SetupStore,
        card: CoffeeCard,
        recipe: Recipe?
    ) {
        if let current = activeBrewer(on: brew, in: setup),
           matches(family, current),
           tab(for: brew.method) == family {
            return
        }
        clearCupboard(from: &brew, setup: setup)
        if let match = setup.equipment.first(where: { isCupboard($0.kind) && matches(family, $0) }) {
            assign(match, to: &brew, setup: setup, card: card, recipe: recipe)
            if tab(for: brew.method) != family {
                brew.method = method(for: match) ?? fallbackMethod(family)
            }
            return
        }
        brew.method = fallbackMethod(family)
        if family == .espresso {
            brew.filterStockId = nil
        }
        BrewPrefill.fill(&brew, card: card, recipe: recipe, setup: setup, replaceKit: false)
        if let leftover = activeBrewer(on: brew, in: setup), !matches(family, leftover) {
            clearCupboard(from: &brew, setup: setup)
        }
    }

    static func assign(
        _ item: Equipment,
        to brew: inout Brew,
        setup: SetupStore,
        card: CoffeeCard,
        recipe: Recipe?
    ) {
        clearCupboard(from: &brew, setup: setup)
        brew.equipmentIDs.append(item.id)
        if let method = method(for: item) {
            brew.method = method
            BrewPrefill.fill(&brew, card: card, recipe: recipe, setup: setup, replaceKit: false)
        }
        if let current = brew.filterStockId.flatMap({ setup.filterStock(id: $0) }),
           FilterFit.compatible(current, with: item) {
            // Keep the paper. Switching dripper must not drop a paper that still fits.
        } else if let paper = FilterFit.default(for: item, in: setup) {
            brew.filterStockId = paper.id
        } else if !item.takesPaper
            || brew.filterStockId.flatMap({ setup.filterStock(id: $0) }) != nil {
            brew.filterStockId = nil
        }
        brew.captureSource = .typed
    }
}
