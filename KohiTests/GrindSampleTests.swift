import Foundation
import Testing
@testable import Kohi

struct GrindSampleTests {
    @Test func aFineSettingIsPowder() {
        let fine = GrindSampleField.count(at: 0)
        let coarse = GrindSampleField.count(at: 1)
        #expect(fine > coarse)
        #expect(fine >= 80)
        #expect(coarse <= 24)
    }

    @Test func thePileDoesNotReshuffle() {
        let a = GrindSampleField.particles(position: 0.4)
        let b = GrindSampleField.particles(position: 0.4)
        #expect(a == b)
    }

    @Test func chipsGetLargerTowardCoarse() {
        let fine = GrindSampleField.particles(position: 0)
        let coarse = GrindSampleField.particles(position: 1)
        let fineMax = fine.map(\.width).max() ?? 0
        let coarseMax = coarse.map(\.width).max() ?? 0
        #expect(coarseMax > fineMax)
    }
}
