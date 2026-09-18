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

nonisolated enum RecipeScaling {
    /// Below this, a pour-over stops behaving like itself. We leave the
    /// author's numbers alone rather than invent a miniature.
    static let minimumDose: Double = 12

    static func roundHalf(_ value: Double) -> Double {
        (value * 2).rounded() / 2
    }

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
        guard let water = recipe.water, water > 0, let ratio = recipe.ratioValue, ratio > 0 else {
            return untouched
        }

        let targetWater = size.waterGrams
        let factor = targetWater / water
        guard abs(factor - 1) >= 0.01 else { return untouched }

        let newDose = roundHalf(targetWater / ratio)
        guard newDose >= minimumDose else { return untouched }
        if let nominalDose, nominalDose < minimumDose { return untouched }

        var copy = recipe
        copy.dose = newDose
        copy.water = targetWater
        copy.steps = recipe.steps.map { step in
            var next = step
            if let mass = step.targetMass {
                next.targetMass = roundHalf(mass * factor)
            }
            return next
        }

        return ScaledRecipe(
            recipe: copy,
            size: size,
            nominalDose: nominalDose,
            nominalWater: nominalWater,
            isScaled: true
        )
    }
}
