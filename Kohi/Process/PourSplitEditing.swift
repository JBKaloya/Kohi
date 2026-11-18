import Foundation

/// What the recipe editor does when a total moves. The ratio is the pivot:
/// the dose carries the water at the same ratio, the water carries the
/// ratio. Either way the parts hold and the grams follow.
nonisolated enum PourSplitEditing {
    /// 15 g to 10 g at 1:15: the water goes to 150 g.
    static func settingDose(
        _ dose: Double?,
        on draft: Recipe,
        countsBloom: Bool,
        shares memorized: [Double]? = nil
    ) -> Recipe {
        var next = draft
        next.dose = dose
        guard let target = liquid(following: dose, from: draft.dose, liquid: RecipeScaling.liquid(of: draft))
        else { return next }
        return settingLiquid(target, on: next, from: draft, countsBloom: countsBloom, shares: memorized)
    }

    /// The water, or the shot on an espresso. The dose stays; the ratio moves.
    static func settingWater(
        _ water: Double?,
        on draft: Recipe,
        countsBloom: Bool,
        shares memorized: [Double]? = nil
    ) -> Recipe {
        guard let water, water > 0 else {
            var next = draft
            if draft.method == .espresso { next.beverage = water } else { next.water = water }
            return next
        }
        return settingLiquid(water, on: draft, from: draft, countsBloom: countsBloom, shares: memorized)
    }

    /// The ratio written: the water comes from the dose.
    static func settingRatio(
        _ ratio: Double?,
        on draft: Recipe,
        countsBloom: Bool,
        shares memorized: [Double]? = nil
    ) -> Recipe {
        guard let ratio, let dose = draft.dose,
              let liquid = PourSplit.water(dose: dose, ratio: ratio)
        else { return draft }
        return settingWater(liquid, on: draft, countsBloom: countsBloom, shares: memorized)
    }

    /// The parts to hold: the ones last written when they still read off
    /// the steps, so half-gram rounding never drifts them; otherwise what
    /// the steps say now.
    static func holding(_ memorized: [Double]?, in steps: [RecipeStep], countsBloom: Bool) -> [Double]? {
        let reached = PourSplit.reached(steps)
        guard reached > 0,
              let split = PourSplit.split(steps: steps, total: reached, countsBloom: countsBloom)
        else { return nil }
        if let memorized, memorized.count == split.services.count,
           PourSplit.percents(of: memorized) == split.percents {
            return memorized
        }
        return split.services.map(\.share)
    }

    /// The liquid a new dose carries at the ratio it had. Nil when there is
    /// no ratio yet to keep: no dose before, none now, or no liquid.
    static func liquid(following dose: Double?, from oldDose: Double?, liquid: Double?) -> Double? {
        guard let dose, dose > 0, let oldDose, oldDose > 0, let liquid, liquid > 0,
              dose != oldDose
        else { return nil }
        return RecipeScaling.roundHalf(liquid / oldDose * dose)
    }

    /// Split shows on every recipe but espresso. Below two pours it says how
    /// to get there instead of disappearing.
    static func showsSplit(_ recipe: Recipe) -> Bool {
        recipe.method != .espresso && RecipeScaling.liquid(of: recipe) != nil
    }

    private static func settingLiquid(
        _ liquid: Double,
        on draft: Recipe,
        from original: Recipe,
        countsBloom: Bool,
        shares memorized: [Double]?
    ) -> Recipe {
        var next = draft
        if draft.method == .espresso { next.beverage = liquid } else { next.water = liquid }
        let shares = holding(memorized, in: original.steps, countsBloom: countsBloom)
        next.steps = PourSplit.resizing(original.steps, to: liquid, shares: shares, countsBloom: countsBloom)
        return next
    }
}
