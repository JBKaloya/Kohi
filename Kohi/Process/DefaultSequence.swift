import Foundation

/// A sequence the timer can follow when the recipe has no steps of its own.
nonisolated enum DefaultSequence {
    static func make(
        family: BrewerFamily,
        brewerType: BrewerType? = nil,
        dose: Double?,
        water: Double?,
        beverage: Double? = nil,
        targetTime: Int?,
        roastLevel: RoastLevel? = nil
    ) -> [RecipeStep] {
        let kind = brewerType ?? fallbackType(family: family)
        switch kind {
        case .espresso:
            return espresso(beverage: beverage ?? water, targetTime: targetTime)
        case .moka:
            return moka()
        case .aeropress:
            return aeroPress(water: water, targetTime: targetTime)
        case .immersionSwitch, .frenchPress:
            return immersion(water: water, targetTime: targetTime)
        case .coldBrew:
            return coldBrew()
        case .batch:
            return batch(water: water, targetTime: targetTime)
        case .v60, .flat, .chemex:
            return percolation(dose: dose, water: water, targetTime: targetTime)
        }
    }

    static func filling(_ recipe: Recipe, type: BrewerType? = nil, roastLevel: RoastLevel? = nil) -> Recipe {
        guard recipe.steps.isEmpty else { return recipe }
        var filled = recipe
        filled.steps = make(
            family: recipe.method.family,
            brewerType: type ?? legacyType(for: recipe.method),
            dose: recipe.dose,
            water: recipe.water,
            beverage: recipe.beverage,
            targetTime: recipe.seconds,
            roastLevel: roastLevel
        )
        return filled
    }

    /// The steps a method actually uses, in the order the canonical sequence
    /// puts them, followed by the universal ones.
    ///
    /// Read off the same sequences the timer follows, so the builder can
    /// never offer Bloom on an espresso while the default sequence does not.
    /// One table, not a switch per screen.
    static func actions(for method: BrewMethod) -> [StepAction] {
        let canonical = make(
            family: method.family,
            brewerType: type(for: method),
            dose: nil,
            water: nil,
            beverage: nil,
            targetTime: nil
        ).map(\.action)

        var ordered: [StepAction] = []
        for action in canonical where !ordered.contains(action) {
            ordered.append(action)
        }
        for action in StepAction.universal where !ordered.contains(action) {
            ordered.append(action)
        }
        return ordered
    }

    /// The brewer type a method implies when no piece of kit is attached.
    /// `BrewerType.method` is many-to-one, so this picks the representative.
    static func type(for method: BrewMethod) -> BrewerType {
        switch method {
        case .v60: .v60
        case .filter: .flat
        case .aeropress: .aeropress
        case .frenchPress: .frenchPress
        case .espresso: .espresso
        case .moka: .moka
        case .coldBrew: .coldBrew
        }
    }

    private static func fallbackType(family: BrewerFamily) -> BrewerType {
        switch family {
        case .handBrew: .v60
        case .batch: .batch
        case .espresso: .espresso
        case .coldBrew: .coldBrew
        }
    }

    /// The sequence a recipe without kit got before Hand brew grouped the
    /// drippers with the immersion brewers: AeroPress, French press and cold
    /// brew recipes still steep rather than pour.
    private static func legacyType(for method: BrewMethod) -> BrewerType {
        switch method {
        case .v60, .filter: .v60
        case .aeropress, .frenchPress, .coldBrew: .frenchPress
        case .espresso, .moka: .espresso
        }
    }

    private static func percolation(dose: Double?, water: Double?, targetTime: Int?) -> [RecipeStep] {
        let dose = dose ?? 15
        let water = water ?? 250
        let total = targetTime ?? max(180, Int((water / 250 * 180).rounded()))
        let bloomMass = min(water, dose * 2)
        let mid = water * 0.6
        let bloomEnd = 45
        let pour2Start = max(bloomEnd + 5, Int(Double(total) * 0.35))
        let pour2End = max(pour2Start + 15, Int(Double(total) * 0.55))
        let lastStart = max(pour2End + 5, Int(Double(total) * 0.65))
        return [
            RecipeStep(at: 0, action: .rinse, targetMass: 150, note: "Skip if the paper is already wet", derived: true),
            RecipeStep(at: 0, action: .bloom, targetMass: bloomMass, untilSeconds: bloomEnd, derived: true),
            RecipeStep(at: bloomEnd, action: .pour, targetMass: mid, untilSeconds: pour2End, derived: true),
            RecipeStep(at: pour2End, action: .wait, untilSeconds: lastStart, derived: true),
            RecipeStep(at: lastStart, action: .pour, targetMass: water, untilSeconds: total, derived: true),
            RecipeStep(at: total, action: .wait, note: "Drawdown", derived: true),
        ]
    }

    private static func immersion(water: Double?, targetTime: Int?) -> [RecipeStep] {
        let water = water ?? 250
        let steep = max(30, (targetTime ?? 240) - 30)
        return [
            RecipeStep(at: 0, action: .rinse, derived: true),
            RecipeStep(at: 0, action: .pour, targetMass: water, untilSeconds: 20, derived: true),
            RecipeStep(at: 20, action: .steep, untilSeconds: steep, derived: true),
            RecipeStep(at: steep, action: .release, derived: true),
        ]
    }

    private static func aeroPress(water: Double?, targetTime: Int?) -> [RecipeStep] {
        let water = water ?? 200
        let steep = 120
        let press = steep + 30
        return [
            RecipeStep(at: 0, action: .rinse, derived: true),
            RecipeStep(at: 0, action: .pour, targetMass: water, untilSeconds: 20, derived: true),
            RecipeStep(at: 20, action: .steep, untilSeconds: steep, derived: true),
            RecipeStep(at: steep, action: .press, untilSeconds: press, derived: true),
        ]
    }

    private static func espresso(beverage: Double?, targetTime: Int?) -> [RecipeStep] {
        let shot = beverage ?? 36
        let total = targetTime ?? 28
        let pre = min(8, max(4, total / 5))
        return [
            RecipeStep(at: 0, action: .preInfusion, untilSeconds: pre, derived: true),
            RecipeStep(at: pre, action: .shot, targetMass: shot, untilSeconds: total, derived: true),
        ]
    }

    private static func moka() -> [RecipeStep] {
        [
            RecipeStep(at: 0, action: .fill, note: "Fill the boiler", derived: true),
            RecipeStep(at: 0, action: .custom, note: "Heat", derived: true),
            RecipeStep(at: 0, action: .custom, note: "Stop at first sputter", derived: true),
        ]
    }

    private static func batch(water: Double?, targetTime: Int?) -> [RecipeStep] {
        let water = water ?? 1000
        let total = targetTime ?? 360
        return [
            RecipeStep(at: 0, action: .fill, targetMass: water, derived: true),
            RecipeStep(at: 0, action: .custom, untilSeconds: total, note: "Brew", derived: true),
            RecipeStep(at: total, action: .custom, note: "Done", derived: true),
        ]
    }

    private static func coldBrew() -> [RecipeStep] {
        [
            RecipeStep(at: 0, action: .steep, note: "Steep 12–18 h in the fridge", derived: true),
        ]
    }
}
