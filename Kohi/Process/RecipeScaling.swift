import Foundation

/// How a recipe is shown, not how it was written.
///
/// A recipe carries its nominal size. The view presents it at 1 cup, 2 cups
/// or batch by scaling dose and water through the ratio and the step masses
/// by the same factor. Times, temperature and grind stay put.
nonisolated enum RecipeSize: String, CaseIterable, Identifiable, Codable, Equatable, Sendable {
    case cup
    case twoCups
    case batch

    var id: String { rawValue }

    var waterGrams: Double {
        switch self {
        case .cup: 250
        case .twoCups: 500
        case .batch: 1000
        }
    }

    var label: String {
        switch self {
        case .cup: "1 cup"
        case .twoCups: "2 cups"
        case .batch: "Batch"
        }
    }

    /// The cup size whose water is closest to what is already in the brew.
    static func inferred(from water: Double?) -> RecipeSize {
        guard let water, water > 0 else { return .cup }
        return allCases.min(by: { abs($0.waterGrams - water) < abs($1.waterGrams - water) }) ?? .cup
    }
}

nonisolated struct ScaledRecipe: Hashable, Sendable {
    var recipe: Recipe
    var size: RecipeSize
    var nominalDose: Double?
    var nominalWater: Double?
    var isScaled: Bool

    var scaledFromLabel: String? {
        guard isScaled, let nominalDose else { return nil }
        return "scaled from \(GrindRange.number(nominalDose)) g"
    }
}

/// The single authority on resizing a recipe.
///
/// Every screen that lets you change a number — the format chips, Today's
/// settings, the step builder, the timer — goes through here. Four copies of
/// this arithmetic is what produced a 60 kg rinse: each one scaled the rinse
/// step, none of them bounded the factor, and they compounded.
nonisolated enum RecipeScaling {
    /// Below this, a pour-over stops behaving like itself. We leave the
    /// author's numbers alone rather than invent a miniature.
    static let minimumDose: Double = 12

    /// Outside this band the "new total" is a half-typed number, not an
    /// intent. Refusing is the only safe reading: a 40x factor turns a 150 g
    /// rinse into 6 kg, and the user never asked for either.
    static let factorBounds: ClosedRange<Double> = 0.2...5

    /// A reading of the water, not a size you pick. About one cup per 250 g.
    static func cupEstimateLabel(for liquid: Double?) -> String? {
        guard let liquid, liquid > 0 else { return nil }
        let cups = max(1, Int((liquid / RecipeSize.cup.waterGrams).rounded()))
        return cups == 1 ? "About 1 cup" : "About \(cups) cups"
    }

    static func roundHalf(_ value: Double) -> Double {
        (value * 2).rounded() / 2
    }

    // MARK: - What a recipe is measured by

    /// Espresso is measured by what lands in the cup; everything else by the
    /// water that goes in. Comparing one against the other is what let an
    /// espresso draft be rescaled against a filter brew's water.
    static func liquid(of recipe: Recipe) -> Double? {
        let value = recipe.method == .espresso
            ? (recipe.beverage ?? recipe.water)
            : (recipe.water ?? recipe.beverage)
        guard let value, value > 0 else { return nil }
        return value
    }

    static func liquid(of brew: Brew) -> Double? {
        let value = brew.method == .espresso
            ? (brew.beverage ?? brew.water)
            : (brew.water ?? brew.beverage)
        guard let value, value > 0 else { return nil }
        return value
    }

    // MARK: - Steps

    /// Scales step masses by a factor.
    ///
    /// **Rinse is never scaled.** Rinse water belongs to the paper, not to
    /// the recipe: a V60 cone takes 150 g whether you brew 250 g or 1 kg.
    /// `RinseRule` owns that number and nothing here may touch it.
    static func scalingSteps(_ steps: [RecipeStep], by factor: Double) -> [RecipeStep] {
        steps.map { step in
            guard step.action != .rinse, let mass = step.targetMass else { return step }
            var next = step
            next.targetMass = roundHalf(mass * factor)
            return next
        }
    }

    // MARK: - The one rescale

    /// Resizes a recipe so its liquid total becomes `target`.
    ///
    /// Returns nil when there is nothing sane to do — no baseline, no change,
    /// or a factor outside `factorBounds`. Callers keep what they had.
    static func rescaled(_ recipe: Recipe, toLiquid target: Double) -> Recipe? {
        guard target > 0, let current = liquid(of: recipe), current > 0 else { return nil }
        let factor = target / current
        guard abs(factor - 1) >= 0.01 else { return nil }
        guard factorBounds.contains(factor) else { return nil }

        var copy = recipe
        copy.steps = scalingSteps(recipe.steps, by: factor)
        if recipe.method == .espresso {
            copy.beverage = target
        } else {
            copy.water = target
        }
        if let dose = recipe.dose, dose > 0 {
            copy.dose = roundHalf(dose * factor)
        }
        return copy
    }

    /// Presentation scaling for the recipe lists: a nominal recipe shown at a
    /// cup size, with the "scaled from" line that goes under the row.
    static func scaled(_ recipe: Recipe, to size: RecipeSize) -> ScaledRecipe {
        let nominalDose = recipe.dose
        let nominalWater = recipe.water
        let untouched = ScaledRecipe(
            recipe: recipe,
            size: size,
            nominalDose: nominalDose,
            nominalWater: nominalWater,
            isScaled: false
        )

        guard recipe.method != .espresso else { return untouched }
        guard let ratio = recipe.ratioValue, ratio > 0 else { return untouched }

        let targetWater = size.waterGrams
        let newDose = roundHalf(targetWater / ratio)
        guard newDose >= minimumDose else { return untouched }
        if let nominalDose, nominalDose < minimumDose { return untouched }

        guard var copy = rescaled(recipe, toLiquid: targetWater) else { return untouched }
        // The list keeps the ratio exactly, so the dose comes from it rather
        // than from the step factor.
        copy.dose = newDose

        return ScaledRecipe(
            recipe: copy,
            size: size,
            nominalDose: nominalDose,
            nominalWater: nominalWater,
            isScaled: true
        )
    }
}
