import Foundation
import Testing
@testable import Kohi

struct BrewControlsTests {
    @Test func aCarryMovesTheOnesColumnForward() {
        let nine = RollMath.counts(of: 9, places: 4)
        let ten = RollMath.counts(of: 10, places: 4)
        #expect(nine == [9, 0, 0, 0])
        // Ones go 9 → 10, which the strip draws as one step forward onto 0.
        #expect(ten == [10, 1, 0, 0])
        #expect(ten[0] == nine[0] + 1)
        #expect(RollMath.jumped(from: Double(nine[0]), to: Double(ten[0]), base: 10) == 9)
    }

    @Test func ninetyNineCarriesIntoTheHundreds() {
        #expect(RollMath.counts(of: 99, places: 4) == [99, 9, 0, 0])
        #expect(RollMath.counts(of: 100, places: 4) == [100, 10, 1, 0])
    }

    @Test func theClockTensRollOverAtSix() {
        let before = RollMath.clockCounts(seconds: 59)
        let after = RollMath.clockCounts(seconds: 60)
        #expect(before.bases == [10, 6, 10, 10])
        #expect(before.counts == [59, 5, 0, 0])
        #expect(after.counts == [60, 6, 1, 0])
        #expect(after.counts[1] == before.counts[1] + 1)
    }

    @Test func aFarColumnJumpsWholeTurns() {
        let jumped = RollMath.jumped(from: 0, to: 80, base: 10)
        #expect(jumped == 60)
        #expect(abs(80 - jumped) <= Motion.rollJumpTurns)
    }

    @Test func aShortGapDoesNotJump() {
        #expect(RollMath.jumped(from: 9, to: 10, base: 10) == 9)
    }

    @Test func rangesClampAndStep() {
        #expect(NumberRange.dose.clamp(0) == 1)
        #expect(NumberRange.dose.clamp(15.04) == 15)
        #expect(NumberRange.dose.clamp(15.06) == 15.1)
        #expect(NumberRange.temperature.clamp(120) == 100)
        #expect(NumberRange.brewTDS.clamp(1.234) == 1.23)
    }

    @Test func sloshSnapsToAWholeScore() {
        #expect(SloshSim.snap(0) == 0)
        #expect(SloshSim.snap(62) == 6)
        #expect(SloshSim.snap(66) == 7)
        #expect(SloshSim.snap(100) == 10)
    }

    @Test func sloshComesToRest() {
        var sim = SloshSim(value: 20)
        sim.fill = 80
        sim.fillVelocity = 4
        for _ in 0..<240 {
            sim.tick(dt: 1)
        }
        #expect(sim.atRest)
        #expect(abs(sim.fill - sim.value) < 0.02)
    }

    @Test func theEndStopGivesSomeBack() {
        var sim = SloshSim(value: 100)
        sim.fill = 100
        sim.fillVelocity = 8
        sim.tick(dt: 1)
        #expect(sim.fill == 100)
        #expect(sim.fillVelocity < 0)
    }

    @Test func aHeldKeyWaitsThenSpeedsUp() {
        #expect(HoldRepeat.arm == 0.38)
        #expect(HoldRepeat.interval(held: 0.5) == 0.09)
        #expect(HoldRepeat.interval(held: 1) == 0.055)
        #expect(HoldRepeat.magnitude(held: 1) == 1)
        #expect(HoldRepeat.magnitude(held: 1.6) == 10)
    }

    @Test func shownPlacesKeepsTheDecimal() {
        #expect(RollMath.shownPlaces(scaled: 150, decimals: 1, places: 4) == 3)
        #expect(RollMath.shownPlaces(scaled: 5, decimals: 1, places: 4) == 2)
    }
}
