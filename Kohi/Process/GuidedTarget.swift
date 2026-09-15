import Foundation

/// Instantaneous mass target inside a pour: where the scale should read now.
nonisolated enum GuidedTarget {
    /// `now = start + (target − start) × (t − tStart) / (tTarget − tStart)`.
    static func massNow(
        startMass: Double,
        targetMass: Double,
        startTime: Double,
        targetTime: Double,
        at time: Double
    ) -> Double {
        let span = targetTime - startTime
        guard span > 0 else { return time >= targetTime ? targetMass : startMass }
        let t = min(max(time, startTime), targetTime)
        return startMass + (targetMass - startMass) * (t - startTime) / span
    }

    /// Previous pour's target mass, or zero at the first pour.
    static func startMass(for steps: [RecipeStep], at index: Int) -> Double {
        steps.prefix(index).reversed().compactMap(\.targetMass).first ?? 0
    }

    /// When this step should be done: `untilSeconds`, else the next step's `at`.
    static func targetTime(for steps: [RecipeStep], at index: Int, total: Int?) -> Double {
        let step = steps[index]
        if let until = step.untilSeconds { return Double(until) }
        if index + 1 < steps.count { return Double(steps[index + 1].at) }
        if let total { return Double(total) }
        return Double(step.at)
    }
}
