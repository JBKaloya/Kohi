import Foundation

/// Edits on the step list that keep its times in step with each other.
nonisolated enum StepEditing {
    /// A step between two others. It starts where the one before ends; a
    /// step that takes a mass starts from the mass already reached, so a
    /// pour inserted there adds nothing until it is told how much.
    static func inserting(_ action: StepAction, after index: Int, in steps: [RecipeStep]) -> [RecipeStep] {
        guard steps.indices.contains(index) else { return steps }
        let previous = steps[index]
        let at = previous.untilSeconds ?? previous.at
        let reached = steps.prefix(index + 1).compactMap(\.targetMass).max()
        var next = steps
        next.insert(RecipeStep(
            at: at,
            action: action,
            targetMass: action.acceptsMass ? (reached ?? 0) : nil,
            untilSeconds: action.hasUntil ? at + 15 : nil
        ), at: index + 1)
        return next
    }

    /// A step's end moved. The next one follows only when it started right
    /// there: a gap or an overlap someone wrote is theirs to keep. No cascade.
    static func settingUntil(_ until: Int?, at index: Int, in steps: [RecipeStep]) -> [RecipeStep] {
        guard steps.indices.contains(index) else { return steps }
        var next = steps
        let old = next[index].untilSeconds
        next[index].untilSeconds = until
        if let old, let until, next.indices.contains(index + 1), next[index + 1].at == old {
            next[index + 1].at = until
        }
        return next
    }
}
