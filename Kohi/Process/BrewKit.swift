import Foundation

/// Shared cupboard resolution for With what, Today's settings, and prefill.
/// A brewer here is a dripper **or** an espresso machine.
@MainActor
enum BrewKit {
    static let journeyTabs: [BrewerFamily] = [.handBrew, .batch, .espresso, .coldBrew]

    static func isCupboard(_ kind: EquipmentKind) -> Bool {
        kind == .brewer || kind == .espressoMachine
    }

    static func activeBrewer(on brew: Brew, in setup: SetupStore) -> Equipment? {
        brew.equipmentIDs.compactMap { setup.equipment(id: $0) }
            .first { isCupboard($0.kind) }
    }

    /// Each family matches only itself — no absorption rules.
    static func matches(_ family: BrewerFamily, _ itemFamily: BrewerFamily?) -> Bool {
        let resolved = itemFamily ?? .handBrew
        return resolved == family
    }

    static func matches(_ family: BrewerFamily, _ item: Equipment) -> Bool {
        self.family(of: item) == family
    }

    static func family(of item: Equipment) -> BrewerFamily {
        if item.kind == .espressoMachine { return .espresso }
        return item.family ?? inferredType(for: item)?.family ?? .handBrew
    }

    /// Whether a brew recording `method` can sit in `family`. A batch brew
    /// records `.filter`, so `.filter` fits Hand brew and Batch brew.
    nonisolated static func accepts(_ family: BrewerFamily, _ method: BrewMethod?) -> Bool {
        guard let method else { return true }
        return method.family == family || (family == .batch && method == .filter)
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
        case .handBrew: .v60
        case .batch: .filter
        case .espresso: .espresso
        case .coldBrew: .coldBrew
        }
    }

    /// The tab a brew sits in: its brewer when known, then the tab just
    /// chosen, then its method. Without the brewer a batch brew would read
    /// as Hand brew, since both record `.filter`.
    static func tab(
        for method: BrewMethod?,
        brewer: Equipment? = nil,
        hint: BrewerFamily? = nil
    ) -> BrewerFamily {
        if let brewer, accepts(family(of: brewer), method) { return family(of: brewer) }
        if let hint, accepts(hint, method) { return hint }
        return method?.journeyTab ?? .handBrew
    }

    static func tab(for brew: Brew, in setup: SetupStore, hint: BrewerFamily? = nil) -> BrewerFamily {
        tab(for: brew.method, brewer: activeBrewer(on: brew, in: setup), hint: hint)
    }

    static func clearCupboard(from brew: inout Brew, setup: SetupStore) {
        brew.equipmentIDs.removeAll { id in
            guard let kind = setup.equipment(id: id)?.kind else { return false }
            return isCupboard(kind)
        }
    }

    /// Switch tab: drop the other family's brewer, never leave a V60 on espresso.
    static func applyFamily(
        _ family: BrewerFamily,
        to brew: inout Brew,
        setup: SetupStore,
        card: CoffeeCard,
        recipe: Recipe?
    ) {
        if let current = activeBrewer(on: brew, in: setup),
           matches(family, current),
           accepts(family, brew.method) {
            return
        }
        clearCupboard(from: &brew, setup: setup)
        if let match = setup.equipment.first(where: { isCupboard($0.kind) && matches(family, $0) }) {
            assign(match, to: &brew, setup: setup, card: card, recipe: recipe)
            if !accepts(family, brew.method) {
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
