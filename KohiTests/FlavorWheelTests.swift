import Foundation
import Testing
@testable import Kohi

struct FlavorWheelTests {
    static let document: FlavorWheelDocument = {
        if FlavorWheel.shared.nodes.count == 111 {
            return FlavorWheel.shared.document
        }
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Kohi/Resources/Reference/flavor-wheel.json")
        return try! FlavorWheel.decode(from: url)
    }()

    @Test func theBundledWheelMatchesTheDeliveredFile() {
        let wheel = Self.document
        #expect(wheel.schema == "kohi.flavor-wheel/1")
        #expect(wheel.nodes.count == 111)
        #expect(wheel.nodes.filter { $0.level == 1 }.count == 9)
        #expect(wheel.nodes.filter { $0.level == 2 }.count == 28)
        #expect(wheel.nodes.filter { $0.level == 3 }.count == 74)
        #expect(wheel.nodes.filter(\.quick).count == 42)
    }

    @Test func familyOrderIsOneThroughNine() {
        let families = Self.document.nodes.filter { $0.level == 1 }.sorted { ($0.order ?? 99) < ($1.order ?? 99) }
        #expect(families.compactMap(\.order) == Array(1...9))
    }

    @Test func everyIdIsUniqueAndEveryParentResolves() {
        let ids = Self.document.nodes.map(\.id)
        #expect(Set(ids).count == ids.count)
        let byID = Dictionary(uniqueKeysWithValues: Self.document.nodes.map { ($0.id, $0) })
        for node in Self.document.nodes {
            if let parent = node.parent {
                #expect(byID[parent] != nil, "orphan parent \(parent) on \(node.id)")
            }
        }
    }

    @Test func originClassesMatchTheHeaderCounts() {
        let counts = Dictionary(grouping: Self.document.nodes.compactMap(\.origin), by: { $0 })
            .mapValues(\.count)
        #expect(counts[.enzymatic] == 54)
        #expect(counts[.dryDistillation] == 20)
        #expect(counts[.defect] == 19)
        #expect(counts[.sugarBrowning] == 18)
        #expect(Set(Self.document.origins.keys) == [
            "enzymatic", "dry-distillation", "defect", "sugar-browning",
        ])
    }

    @Test func sharedLoadsTheSameWheel() {
        #expect(FlavorWheel.shared.nodes.count == 111)
        #expect(FlavorWheel.shared.families.count == 9)
        #expect(FlavorWheel.shared.quick.count == 42)
    }
}
