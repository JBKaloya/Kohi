import ActivityKit
import Foundation
import os

/// Local Live Activity for the guided pour. Updates about once a second;
/// ends with the timer. Failures are silent — a brew does not depend on it.
@MainActor
enum BrewLiveActivity {
    private static var activity: Activity<BrewActivityAttributes>?
    private static var lastSecond = -1

    static func start(
        card: CoffeeCard,
        recipe: Recipe,
        brew: Brew,
        index: Int,
        elapsed: TimeInterval,
        startedAt: Date
    ) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        end()
        let attributes = BrewActivityAttributes(
            coffeeName: card.displayName,
            methodLabel: (brew.method ?? recipe.method).label
        )
        let state = content(
            recipe: recipe,
            brew: brew,
            index: index,
            elapsed: elapsed,
            startedAt: startedAt
        )
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil)
            )
            lastSecond = Int(elapsed)
        } catch {
            Log.app.notice("live activity could not start: \(error)")
        }
    }

    static func update(
        recipe: Recipe,
        brew: Brew,
        index: Int,
        elapsed: TimeInterval,
        startedAt: Date,
        force: Bool = false
    ) {
        let second = Int(elapsed)
        guard force || second != lastSecond else { return }
        lastSecond = second
        guard let activity else { return }
        let state = content(
            recipe: recipe,
            brew: brew,
            index: index,
            elapsed: elapsed,
            startedAt: startedAt
        )
        Task { await activity.update(.init(state: state, staleDate: nil)) }
    }

    static func end() {
        let current = activity
        activity = nil
        lastSecond = -1
        guard let current else { return }
        Task { await current.end(nil, dismissalPolicy: .immediate) }
    }

    private static func content(
        recipe: Recipe,
        brew: Brew,
        index: Int,
        elapsed: TimeInterval,
        startedAt: Date
    ) -> BrewActivityAttributes.ContentState {
        let steps = recipe.steps
        let masses = steps.compactMap(\.targetMass)
        let final = GuidedTarget.finalMass(steps: steps, water: recipe.water ?? brew.water)
        let now: Double? = steps.isEmpty ? brew.water : GuidedTarget.currentMass(
            steps: steps,
            index: index,
            elapsed: elapsed,
            total: recipe.seconds
        )
        let target: Double?
        if index < steps.count {
            target = steps[index].targetMass
        } else {
            target = masses.last
        }
        let label: String
        if steps.isEmpty {
            label = "Brewing"
        } else if index >= steps.count {
            label = "Done"
        } else {
            label = steps[index].instruction
        }
        return BrewActivityAttributes.ContentState(
            stepLabel: label,
            nowMass: now,
            targetMass: target,
            finalMass: final,
            stepMasses: masses,
            stepIndex: min(index, max(steps.count, 1)),
            stepCount: max(steps.count, 1),
            startedAt: startedAt
        )
    }
}
