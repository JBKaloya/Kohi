import Foundation

/// A grind setting translated into another grinder's units, with the basis for
/// the translation attached.
///
/// The basis is not a footnote. A number derived from your own calibration and
/// a number derived from a published range are different kinds of claim, and
/// showing them identically would be the single most misleading thing this
/// module could do.
nonisolated struct GrindTranslation: Hashable, Sendable {
    /// The setting in the target grinder's units.
    var setting: Double
    var adjustment: GrindAdjustment?
    var basis: Basis
    /// Set when the arithmetic landed outside the target grinder's declared
    /// range and had to be pulled back to the edge.
    var wasClamped: Bool

    nonisolated enum Basis: Hashable, Sendable {
        /// Your own calibration for this grinder and method.
        case calibration
        /// Both grinders' declared ranges for the method.
        case declaredRanges
        /// The target grinder's declared range, against a published particle
        /// size band for the method.
        case methodRange
        /// A published range for this grinder and method, with its source.
        case published(String)
        /// The maker's microns per step, scaled within one grinder.
        case makerStep

        /// The line that goes in the `tag` column, and the reason the number
        /// can be trusted as much or as little as it deserves.
        var label: String {
            switch self {
            case .calibration: "from your calibration"
            case .declaredRanges: "from your ranges"
            case .methodRange: "from range"
            case .published(let source): "≈ · from \(source)"
            case .makerStep: "from maker step"
            }
        }

        /// Whether this rests on something you measured, rather than on
        /// somebody's rule of thumb.
        var isYours: Bool {
            switch self {
            case .calibration, .declaredRanges: true
            case .methodRange, .makerStep, .published: false
            }
        }
    }

    /// "≈ 22 clicks" — always with the approximation sign, in every basis.
    /// There is no case where this arithmetic produces an exact answer.
    var label: String {
        let number = GrindRange.number(setting)
        switch adjustment {
        case .clicks: return "≈ \(number) clicks"
        case .dial: return "≈ \(number) on the dial"
        case .stepless, .none: return "≈ \(number)"
        }
    }

    /// The full line: the number, then what it rests on.
    var detailedLabel: String {
        var line = "\(label) · \(basis.label)"
        if wasClamped { line += " · at the edge of your range" }
        return line
    }
}

/// Translating grind settings between grinders (annexe G8).
///
/// Two stages, both approximate, both stated as such:
///
/// 1. Within one grinder, settings scale by the maker's microns per step. That
///    is burr travel, so it is a fair proxy for "how much finer is 20 than 24"
///    on the same machine and worthless across two.
/// 2. Between grinders, the useful range each one covers for a method is
///    mapped onto the other. Your declared ranges first; the reference base's
///    indicative hints only when you have declared nothing.
///
/// A calibration you entered short-circuits both. The collective calibration —
/// observed pairs from many users — is v2, and until it exists this module
/// tells you when it is guessing.
nonisolated enum GrindConversion {
    // MARK: - Within one grinder

    /// A setting expressed as burr travel, for comparing two settings on the
    /// same grinder. Mechanical displacement, never a particle size.
    static func micronProxy(setting: Double, grinder: Equipment) -> Double? {
        guard let perStep = grinder.makerMicronsPerStep, perStep > 0 else { return nil }
        return setting * perStep
    }

    /// How many notches to move to change the grind by a given proportion.
    /// Used by the diagnostic rules, which think in "a little finer".
    static func settingShift(
        from setting: Double,
        by fraction: Double,
        grinder: Equipment
    ) -> Double {
        let moved = setting * (1 + fraction)
        return round(moved, for: grinder)
    }

    // MARK: - Between grinders

    /// The recipe's grind, read in your grinder's units.
    ///
    /// Returns nil rather than a number when there is nothing to base it on:
    /// an invented setting is worse than a verbal "medium-fine", because it
    /// looks like it was measured.
    static func translate(
        recipe: Recipe,
        to target: Equipment,
        calibrations: [GrindCalibration] = [],
        shift: Int = 0
    ) -> GrindTranslation? {
        let method = recipe.method

        // Your own calibration wins: it is the only figure here that came from
        // coffee rather than from arithmetic.
        if let calibration = calibrations.first(
            where: { $0.grinderID == target.id && $0.method == method }
        ) {
            let setting = applyShift(calibration.setting, shift: shift, grinder: target)
            return GrindTranslation(
                setting: round(setting, for: target),
                adjustment: target.adjustment,
                basis: .calibration,
                wasClamped: false
            )
        }

        guard let targetRange = target.range(for: method) else { return nil }

        // Where the recipe's grind sits inside the method's published band,
        // mapped onto where your range sits.
        let position = recipePosition(recipe)
        let raw = targetRange.low + position * targetRange.span
        let shifted = applyShift(raw, shift: shift, grinder: target)
        let clamped = clamp(shifted, to: targetRange)

        return GrindTranslation(
            setting: round(clamped, for: target),
            adjustment: target.adjustment,
            basis: recipe.grindMicronsLow == nil ? .declaredRanges : .methodRange,
            wasClamped: clamped != shifted
        )
    }

    /// A setting on one grinder, read on another (annexe G8, stage 2):
    /// `settingB = minB + (settingA − minA) ÷ (maxA − minA) × (maxB − minB)`.
    static func translate(
        setting: Double,
        method: BrewMethod,
        from source: Equipment,
        to target: Equipment,
        calibrations: [GrindCalibration] = []
    ) -> GrindTranslation? {
        if let calibration = calibrations.first(
            where: { $0.grinderID == target.id && $0.method == method }
        ) {
            return GrindTranslation(
                setting: round(calibration.setting, for: target),
                adjustment: target.adjustment,
                basis: .calibration,
                wasClamped: false
            )
        }

        guard let sourceRange = range(for: method, on: source),
              let targetRange = range(for: method, on: target)
        else { return nil }

        // A degenerate source range carries no information about where inside
        // it the setting sits, so the target's own midpoint is the only honest
        // answer.
        let position = sourceRange.span > 0
            ? (setting - sourceRange.low) / sourceRange.span
            : 0.5
        let raw = targetRange.low + position * targetRange.span
        let clamped = clamp(raw, to: targetRange)

        let declared = source.range(for: method) != nil && target.range(for: method) != nil
        return GrindTranslation(
            setting: round(clamped, for: target),
            adjustment: target.adjustment,
            basis: declared ? .declaredRanges : .methodRange,
            wasClamped: clamped != raw
        )
    }

    // MARK: - Ranges

    /// Your declared range for a method, falling back to the reference base's
    /// indicative hint. The caller can tell which it got by checking
    /// `equipment.range(for:)` itself — the translation records it in `basis`.
    static func range(for method: BrewMethod, on grinder: Equipment) -> GrindRange? {
        if let declared = grinder.range(for: method) { return declared }
        if let published = PublishedGrindRanges.range(grinderRef: grinder.grinderRef, method: method) {
            return published
        }
        guard let ref = grinder.grinderRef,
              let reference = ReferenceBase.grinder(id: ref),
              let hint = reference.ranges?.first(where: { $0.method == method })
        else { return nil }
        return hint
    }

    /// Where a recipe's grind sits within its method's published particle-size
    /// band, as a fraction from 0 (the fine end) to 1 (the coarse end).
    ///
    /// With no microns on the recipe, the middle of the range is the answer:
    /// a reference recipe's grind is, by construction, the ordinary setting for
    /// that method.
    static func recipePosition(_ recipe: Recipe) -> Double {
        guard let low = recipe.grindMicronsLow,
              let band = RecipeRules.microns(for: recipe.method)
        else { return 0.5 }

        let midpoint = ((recipe.grindMicronsHigh ?? low) + low) / 2
        let span = band.upperBound - band.lowerBound
        guard span > 0 else { return 0.5 }
        let position = (midpoint - band.lowerBound) / span
        return min(max(position, 0), 1)
    }

    // MARK: - Arithmetic

    /// One notch of shift means one notch on a detented grinder, and a
    /// twentieth of the useful range on a stepless one — where "one click"
    /// does not exist.
    private static func applyShift(
        _ setting: Double,
        shift: Int,
        grinder: Equipment
    ) -> Double {
        guard shift != 0 else { return setting }
        guard grinder.adjustment?.isDetented ?? true else {
            return setting * (1 + 0.05 * Double(shift))
        }
        return setting + Double(shift)
    }

    private static func clamp(_ value: Double, to range: GrindRange) -> Double {
        min(max(value, range.low), range.high)
    }

    /// A detented grinder cannot be set to 22.4, so the number is rounded to
    /// the notch. A stepless one keeps a decimal, because it can be dialled.
    static func round(_ value: Double, for grinder: Equipment) -> Double {
        switch grinder.adjustment {
        case .clicks: value.rounded()
        case .dial, .stepless, .none: (value * 10).rounded() / 10
        }
    }

    static func forYourGrinder(
        recipe: Recipe,
        grinder: Equipment?,
        calibrations: [GrindCalibration] = [],
        shift: Int = 0
    ) -> ForYourGrinder {
        guard let grinder else { return .addGrinder }
        guard let translation = translate(
            recipe: recipe,
            to: grinder,
            calibrations: calibrations,
            shift: shift
        ) else { return .noRange }
        let brand = grinder.brand.trimmingCharacters(in: .whitespaces)
        return .translated(
            translation,
            grinderName: brand.isEmpty ? grinder.displayName : brand
        )
    }
}

/// What the recipe detail and Suggested recipe row show for the grind.
nonisolated enum ForYourGrinder: Equatable, Sendable {
    case translated(GrindTranslation, grinderName: String)
    case noRange
    case addGrinder

    var line: String {
        switch self {
        case .translated(let translation, let name):
            return "\(translation.label) · \(name)"
        case .noRange:
            return "No click range on file for this grinder yet"
        case .addGrinder:
            return "Add your grinder to see this in clicks"
        }
    }

    var opensKit: Bool {
        switch self {
        case .addGrinder: true
        case .translated, .noRange: false
        }
    }
}
