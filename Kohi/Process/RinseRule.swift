import Foundation

/// Indicative rinse mass by paper geometry. Injected at the head of the
/// timer recipe, never stored on Mine or From the pros.
nonisolated enum RinseRule {
    /// Grams of hot water, or nil when the instruction is "rinse until clear".
    static func mass(for shape: FilterShape, unbleached: Bool = false) -> Double? {
        if unbleached { return 150 }
        switch shape {
        case .cone60, .coneDeep, .melitta, .dedicated, .ufo: return 150
        case .wave, .flatSmooth: return 100
        case .chemex: return 600
        case .disc: return 50
        case .cloth: return nil
        case .basket: return nil
        }
    }

    static func mass(for stock: FilterStock?, brewer: Equipment, override: Double? = nil) -> Double? {
        if let override { return override }
        let shape = stock?.resolvedShape
            ?? brewer.resolvedFilterShapes.first
        guard let shape, shape.takesRinse else { return nil }
        let unbleached = stock?.model?.isUnbleached == true
            && (stock?.model?.brand.localizedCaseInsensitiveContains("hario") == true)
        return mass(for: shape, unbleached: unbleached)
    }

    static func caption(for stock: FilterStock?, brewer: Equipment, override: Double? = nil) -> String? {
        guard let shape = stock?.resolvedShape ?? brewer.resolvedFilterShapes.first,
              shape.takesRinse
        else { return nil }
        var parts: [String] = []
        if let flow = stock?.model?.flowClass, stock?.model?.showsFlowClass == true {
            parts.append(flow.tag)
        }
        if let grams = mass(for: stock, brewer: brewer, override: override) {
            parts.append("rinse \(GrindRange.number(grams)) g")
        } else if shape == .cloth {
            parts.append("rinse until clear")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func step(
        for stock: FilterStock?,
        brewer: Equipment,
        override: Double? = nil
    ) -> RecipeStep? {
        let shapes = brewer.resolvedFilterShapes
        guard !shapes.isEmpty else { return nil }
        let shape = stock?.resolvedShape ?? shapes.first
        guard let shape, shape.takesRinse else { return nil }
        let grams = mass(for: stock, brewer: brewer, override: override)
        let note: String
        if shape == .cloth, grams == nil {
            note = "until clear"
        } else {
            note = "hot water"
        }
        return RecipeStep(at: 0, action: .rinse, targetMass: grams, note: note)
    }

    /// Prepends a rinse when the day's brewer takes paper or cloth.
    static func injecting(
        into recipe: Recipe,
        brewer: Equipment?,
        stock: FilterStock?
    ) -> Recipe {
        guard let brewer else { return recipe }
        guard let rinse = step(for: stock, brewer: brewer, override: recipe.rinseMassOverride)
        else { return recipe }
        if recipe.steps.first?.action == .rinse { return recipe }
        var next = recipe
        next.steps.insert(rinse, at: 0)
        return next
    }
}