import Foundation
import Testing
@testable import Kohi

struct PourFillProgressTests {
    private let steps = [
        RecipeStep(at: 0, action: .bloom, targetMass: 60),
        RecipeStep(at: 45, action: .pour, targetMass: 300),
        RecipeStep(at: 75, action: .wait),
    ]

    @Test func fillIsTheShareOfTheFinalMass() {
        let fill = GuidedTarget.fill(
            steps: steps,
            index: 0,
            elapsed: 0,
            total: 210,
            water: 300
        )
        #expect(abs(fill - 0) < 0.001)
        let mid = GuidedTarget.fill(
            steps: steps,
            index: 0,
            elapsed: 22.5,
            total: 210,
            water: 300
        )
        #expect(abs(mid - 0.1) < 0.001)
    }

    @Test func fillClampsWhenTheStepOverruns() {
        let fill = GuidedTarget.fill(
            steps: steps,
            index: 1,
            elapsed: 400,
            total: 210,
            water: 300
        )
        #expect(fill == 1)
    }

    @Test func aWaitHoldsTheTide() {
        let atPourEnd = GuidedTarget.currentMass(
            steps: steps,
            index: 1,
            elapsed: 75,
            total: 210
        )
        let duringWait = GuidedTarget.currentMass(
            steps: steps,
            index: 2,
            elapsed: 90,
            total: 210
        )
        #expect(atPourEnd == 300)
        #expect(duringWait == 300)
    }

    @Test func espressoHasNoTide() {
        #expect(GuidedTarget.showsTide(.v60))
        #expect(GuidedTarget.showsTide(.filter))
        #expect(!GuidedTarget.showsTide(.espresso))
        #expect(!GuidedTarget.showsTide(.moka))
        #expect(!GuidedTarget.showsRings(.filter))
        #expect(GuidedTarget.showsRings(.v60))
    }

    @Test func v60RingsFollowThePoursAndHold() {
        #expect(GuidedTarget.activeRing(steps: steps, index: 0) == 0)
        #expect(GuidedTarget.activeRing(steps: steps, index: 1) == 1)
        #expect(GuidedTarget.activeRing(steps: steps, index: 2) == 1)
    }

    @Test func noMassMeansNoFill() {
        let empty = GuidedTarget.fill(
            steps: [RecipeStep(at: 0, action: .stir)],
            index: 0,
            elapsed: 10,
            total: 30,
            water: nil
        )
        #expect(empty == 0)
    }
}
