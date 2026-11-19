import Foundation
import Testing
@testable import Kohi

/// Live narrations as French brewers say them, and the evaluation set.
struct FrenchNarrationTests {
    private func steps(_ text: String, at: TimeInterval = 0, water: Double? = nil) -> [SpokenBrewParser.TimedStep] {
        SpokenBrewParser.timedSteps(phrases: [.init(at: at, text: text)], water: water)
    }

    @Test func pouringByStepsOfFortyBecomesThePoursItDescribes() {
        let heard = steps(
            "Puis ensuite je verse par palier de 40, j'attends 20 secondes entre chaque et je finis jusqu'à 200",
            at: 30
        )
        #expect(heard.map(\.mass) == [40, 80, 120, 160, 200])
        #expect(heard.map(\.at) == [30, 50, 70, 90, 110])
        #expect(heard.allSatisfy { $0.action == .pour })
    }

    @Test func aPatternWithoutItsTargetEndsOnTheWater() {
        let heard = steps("je verse par palier de 50 toutes les 15 secondes", at: 45, water: 200)
        #expect(heard.map(\.mass) == [50, 100, 150, 200])
        #expect(heard.map(\.at) == [45, 60, 75, 90])
    }

    @Test func aPatternCountsFromTheMassAlreadyReached() {
        let heard = SpokenBrewParser.timedSteps(phrases: [
            .init(at: 3, text: "Bloom 40 grammes."),
            .init(at: 45, text: "Ensuite par paliers de 70 jusqu'à 250."),
        ])
        #expect(heard.map(\.mass) == [40, 110, 180, 250])
    }

    @Test func frenchVerbsAndWordsAreRead() {
        #expect(steps("je verse jusqu'à cent cinquante grammes").map(\.mass) == [150])
        #expect(steps("j'ai versé deux cent cinquante").map(\.mass) == [250])
        #expect(steps("je fais un bloom de quarante grammes").map(\.mass) == [40])
        #expect(steps("j'attends trente secondes").first?.action == .wait)
        #expect(steps("deuxième versement à 250, plus lent").first?.note == "plus lent")
    }

    @Test func aTimeIsNeverReadAsAMass() {
        let heard = steps("je verse doucement, j'attends 20 secondes")
        #expect(!heard.contains { $0.action == .pour && $0.mass == 20 })
    }

    @Test func moreIsCountedFromTheLastReading() {
        let heard = SpokenBrewParser.timedSteps(phrases: [
            .init(at: 20, text: "Je verse jusqu'à 150."),
            .init(at: 40, text: "Puis encore 100 grammes."),
            .init(at: 60, text: "50 de plus."),
        ])
        #expect(heard.map(\.mass) == [150, 250, 300])
    }

    @Test func secondesAreATime() {
        #expect(SpokenBrewParser.parse("temps total 150 secondes").seconds == 150)
    }

    @Test func theEvaluationSetIsHeard() throws {
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "Fixtures/Dictations")
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        #expect(!files.isEmpty)
        for file in files {
            let set = try JSONDecoder().decode(Case.self, from: Data(contentsOf: file))
            let heard = SpokenBrewParser.timedSteps(
                phrases: set.phrases.map { .init(at: $0.at, text: $0.text) },
                water: set.water
            )
            #expect(heard.map(\.action.rawValue) == set.expected.map(\.action), "\(set.name)")
            #expect(heard.map(\.mass) == set.expected.map(\.mass), "\(set.name)")
            #expect(heard.map(\.at) == set.expected.map(\.at), "\(set.name)")
        }
    }

    private struct Case: Decodable {
        struct Phrase: Decodable { var at: Double; var text: String }
        struct Step: Decodable { var at: Int; var action: String; var mass: Double? }
        var name: String
        var water: Double?
        var phrases: [Phrase]
        var expected: [Step]
    }
}
