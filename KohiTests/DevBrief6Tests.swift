import Foundation
import Testing
@testable import Kohi

@MainActor
struct DevBrief6CorrectionTests {
    @Test func brewAgainAppliesTheChosenGrindMove() {
        let setup = SetupStore(files: JSONDocumentStore(filename: "setup-brief6-\(UUID().uuidString).json"))
        var last = Brew(method: .v60, dose: 15, water: 250, grind: GrindSetting(value: 22))
        last.bitterness = 1
        last.acidity = 0
        last.nextTimeSuggestion = "grind coarser"

        let prepared = BrewPrefill.preparedAgain(from: last, setup: setup)
        #expect(prepared.application?.change == "grind coarser")
        #expect(prepared.brew.grind.value == 23)
        #expect(prepared.brew.id != last.id)

        let session = BrewSession(
            card: CoffeeCard(name: "Test"),
            existing: prepared.brew,
            start: .kit,
            lastApplication: prepared.application,
            setup: setup
        )
        #expect(session.brew.grind.value == 23)
        session.undoLastApplication()
        #expect(session.brew.grind.value == 22)
        #expect(session.lastApplication == nil)
    }

    @Test func brewAgainWithoutAMoveCopiesTheCup() {
        let setup = SetupStore(files: JSONDocumentStore(filename: "setup-brief6-\(UUID().uuidString).json"))
        let last = Brew(method: .v60, dose: 15, water: 250, grind: GrindSetting(value: 22))
        let prepared = BrewPrefill.preparedAgain(from: last, setup: setup)
        #expect(prepared.application == nil)
        #expect(prepared.brew.grind.value == 22)
    }
}

struct DevBrief6NumberTests {
    @Test func aTrailingDecimalStillParses() {
        #expect(NumberText.parse("15.") == 15)
        #expect(NumberText.parse("15,5") == 15.5)
        #expect(NumberText.parse("") == nil)
    }
}

struct DevBrief6ReadingTests {
    @Test func sweetnessInTheNoteBecomesAnIntent() {
        let intents = TastingIntent.extract("manque de douceur, trop peu de complexité")
        #expect(intents.contains { $0.axis == .sweetness && $0.direction == -1 })
        #expect(intents.contains { $0.axis == .complexity && $0.direction == -1 })
        #expect(TastingIntent.understoodLine(intents)?.contains("sweetness") == true)
        #expect(TastingIntent.extract("bon").isEmpty)
        #expect(TastingIntent.understoodLine(for: "bon") == "Understood: nothing to correct")
    }

    @Test func narrationKeepsTheMassYouSaid() {
        #expect(NarrationDeviation.parse("finalement bloom").isEmpty)
        let said = NarrationDeviation.parse("bloom, finalement au lieu de 30")
        #expect(said.first?.mass == 30)
    }

    @Test func classicWaterAt50IsAConcentrate() {
        let advice = MineralCalculator.advise(productID: "tww-classic", targetPpm: 50)
        #expect(advice?.line.contains("1 part with 2 parts") == true)
        #expect(MineralCalculator.advise(productID: "lotus-water", targetPpm: 50) == nil)
    }

    @Test func kUltraPourOverIsPublished() {
        let row = PublishedGrindRanges.match(grinderRef: "1zpresso-k-ultra", method: .v60)
        #expect(row?.min == 80)
        #expect(row?.max == 90)
        #expect(PublishedGrindRanges.caption(grinderRef: "1zpresso-k-ultra", method: .filter)?.contains("1Zpresso") == true)
        #expect(PublishedGrindRanges.match(grinderRef: "1zpresso-k-plus", method: .v60) == nil)
    }
}

struct DevBrief6GestureInventoryTests {
    @Test func noHighPriorityZeroDistanceDrag() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Kohi")
        let files = try FileManager.default.subpathsOfDirectory(atPath: root.path)
        for relative in files where relative.hasSuffix(".swift") {
            let text = try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
            let collapsed = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            #expect(
                !collapsed.contains("highPriorityGesture( DragGesture(minimumDistance: 0)"),
                "\(relative) claims the scroll with a zero-distance drag"
            )
        }
    }
}
