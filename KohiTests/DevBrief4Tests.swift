import Foundation
import Testing
@testable import Kohi

struct GuidedTargetTests {
    @Test func aPourInterpolatesLinearlyThroughTheStep() {
        let now = GuidedTarget.massNow(
            startMass: 60,
            targetMass: 300,
            startTime: 45,
            targetTime: 75,
            at: 60
        )
        #expect(abs(now - 180) < 0.01)
    }

    @Test func beforeTheStepTheMassStaysAtTheStart() {
        let now = GuidedTarget.massNow(
            startMass: 60,
            targetMass: 300,
            startTime: 45,
            targetTime: 75,
            at: 10
        )
        #expect(now == 60)
    }

    @Test func afterTheStepTheMassIsTheTarget() {
        let now = GuidedTarget.massNow(
            startMass: 60,
            targetMass: 300,
            startTime: 45,
            targetTime: 75,
            at: 90
        )
        #expect(now == 300)
    }

    @Test func startMassIsThePreviousPourTarget() {
        let steps = [
            RecipeStep(at: 0, action: .bloom, targetMass: 60),
            RecipeStep(at: 45, action: .pour, targetMass: 300),
        ]
        #expect(GuidedTarget.startMass(for: steps, at: 1) == 60)
        #expect(GuidedTarget.startMass(for: steps, at: 0) == 0)
    }
}

struct SuggestedCorrectionTests {
    private func allowedSet() -> [NextTime] {
        [
            NextTime(change: "grind finer", reason: "more contact", variable: .grind, direction: -1, evidence: .practice),
            NextTime(change: "Lengthen the bloom by 15 s", reason: "wetting", variable: .steps, direction: 1, evidence: .practice),
            NextTime(change: "Stir after pour 2", reason: "bed", variable: .agitation, direction: 1, evidence: .practice),
        ]
    }

    @Test func validJSONKeepsThreeRankedMovesFromTheSet() {
        let payload = """
        {"reading":"Sour.","target":"more extraction","moves":[
          {"rank":1,"variable":"grind","change":"grind finer","why":"more contact"},
          {"rank":2,"variable":"steps","change":"Lengthen the bloom by 15 s","why":"wetting"},
          {"rank":3,"variable":"agitation","change":"Stir after pour 2","why":"bed"}
        ]}
        """.data(using: .utf8)!
        let valid = SuggestedCorrection.validated(payload, allowed: allowedSet())
        #expect(valid != nil)
        #expect(valid?.moves.count == 3)
        #expect(valid?.moves.map(\.rank) == [1, 2, 3])
        #expect(Set(valid?.moves.map(\.variable) ?? []).count == 3)
    }

    @Test func aMoveOutsideTheSetIsRejected() {
        let data = """
        {"reading":"x","target":"y","moves":[
          {"rank":1,"variable":"magic","change":"teleport the slurry","why":"no"},
          {"rank":2,"variable":"magic","change":"invent a dripper","why":"no"},
          {"rank":3,"variable":"magic","change":"boil the moon","why":"no"}
        ]}
        """.data(using: .utf8)!
        #expect(SuggestedCorrection.validated(data, allowed: allowedSet()) == nil)
    }

    @Test func twoMovesInsteadOfThreeAreRejected() {
        let data = """
        {"reading":"x","target":"y","moves":[
          {"rank":1,"variable":"grind","change":"grind finer","why":"a"},
          {"rank":2,"variable":"steps","change":"Lengthen the bloom by 15 s","why":"b"}
        ]}
        """.data(using: .utf8)!
        #expect(SuggestedCorrection.validated(data, allowed: allowedSet()) == nil)
    }

    @Test func fallbackIsTheHighestPriorityRule() {
        let brew = BrewDiagnosisTests.brew(acidity: 1)
        let correction = SuggestedCorrection.fallback(from: brew)
        #expect(correction?.moves.count == 1)
        #expect(correction?.isModel == false)
        #expect(correction?.moves.first?.variable == "grind")
    }

    @Test func twoDrippersOfferABypassMoveWhenTheCupWantsClarity() {
        let v60 = Equipment(kind: .brewer, brand: "Hario", model: "V60", brewerRef: "dripper-002")
        let switcher = Equipment(kind: .brewer, brand: "Hario", model: "Switch", brewerRef: "dripper-005")
        let brew = BrewDiagnosisTests.brew(acidity: 1)
        let moves = BrewDiagnosis.dripperMoves(for: brew, equipment: [v60, switcher])
        #expect(moves.contains { $0.variable == .dripper })
        #expect(BrewDiagnosis.dripperMoves(for: brew, equipment: [v60]).isEmpty)
    }
}

struct AIFeedbackTests {
    @Test func aScoreIsRequiredAndTheCSVHasAHeader() {
        let item = AIFeedback(feature: .ask, score: .useful, comment: "clearer")
        #expect(item.score.rawValue == 3)
        let csv = ([AIFeedback.csvHeader] + [item.csvLine]).joined(separator: "\n")
        #expect(csv.contains("id,feature,score,comment,created_at"))
        #expect(csv.contains("ask"))
        #expect(csv.contains("3"))
        #expect(!csv.split(separator: "\n").dropFirst().isEmpty)
    }
}

struct VocabTests {
    @Test func theUserFacingCopyUsesTheAgreedWords() {
        #expect(Copy.whiten == "Whiten")
        #expect(Copy.suggestedCorrection == "Suggested correction")
        #expect(Copy.forYourGrinder == "For your grinder")
        #expect(Copy.dictate == "Dictate")
        #expect(Copy.fromThePros == "From the pros")
        #expect(Copy.features == "Features")
        #expect(RecipeTab.reference.label == Copy.fromThePros)
        #expect(Copy.coffeeDose == "Coffee dose")
        #expect(Copy.waterWeight == "Water weight")
        #expect(Copy.roastedOn == "Roasted on")
        #expect(RecipeProvenance.reference("").listLabel == Copy.fromThePros)
        #expect(RecipeProvenance.reference("").label == Copy.fromThePros)
    }

    @Test func theScanReviewDoesNotCallTheFilterWashed() throws {
        let source = try String(contentsOfFile: "\(Self.kohiRoot.path)/Scan/ScanReviewScreen.swift")
        #expect(source.contains("Copy.whiten"))
        #expect(!source.contains("Text(\"Washed\")"))
        #expect(!source.contains("\"Say it\""))
        #expect(!source.contains("In your terms"))
        #expect(!source.contains("Next time"))
    }

    @Test func viewsDoNotKeepTheOldWords() throws {
        let files = [
            "Recipes/RecipeTabs.swift",
            "Setup/ProfileSheet.swift",
            "Recipes/RecipeDetailSheet.swift",
            "Edit/BrewSheet.swift",
            "Detail/CaptionBlock.swift",
            "Grid/GridScreen.swift",
        ]
        for file in files {
            let text = try String(contentsOf: Self.kohiRoot.appending(path: file))
            #expect(!text.contains("\"Say it\""), "\(file) still says Say it")
            #expect(!text.contains("In your terms"), "\(file) still says In your terms")
            #expect(!text.contains("\"Surfaces\""), "\(file) still says Surfaces")
        }
    }

    fileprivate static var kohiRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Kohi")
    }
}

struct DictationFieldInventoryTests {
    @Test func theListedFreeTextFilesCallDictationField() throws {
        let files = [
            "Edit/CardEditSheet.swift",
            "Edit/BrewSheet.swift",
            "AI/AskSheet.swift",
            "Recipes/AfterBrewSheet.swift",
            "Recipes/RecipeEditSheet.swift",
            "Edit/RoasterSheet.swift",
            "Edit/TagField.swift",
            "Setup/GrindConverterSheet.swift",
            "Setup/EquipmentSheet.swift",
            "Setup/WaterSheet.swift",
            "AI/AIFeedbackScale.swift",
        ]
        for file in files {
            let text = try String(contentsOf: VocabTests.kohiRoot.appending(path: file))
            #expect(text.contains("DictationField"), "missing in \(file)")
        }
    }
}

struct MineralProductTests {
    @Test func theRecipeModeCatalogueHasTwelveProducts() {
        #expect(ReferenceBase.mineralProducts.count >= 12)
        #expect(ReferenceBase.mineralProducts.contains { $0.id == "akvo-minerals" })
        #expect(ReferenceBase.mineralProducts.contains { $0.id == "tww-classic" && $0.compositionOnFile })
        #expect(ReferenceBase.mineralProducts.contains { $0.id == "akvo-minerals" && !$0.compositionOnFile })
    }
}

struct RecipeFlowScreenTests {
    @Test func aReferenceRecipeHasAGuidedClockAndAfterSheetInputs() {
        let recipe = ReferenceBase.recipe(referenceID: "a1-v60-ultimate")
        #expect(recipe?.steps.isEmpty == false)
        #expect(recipe?.autoAdvance == true)
        #expect(recipe?.steps.contains { $0.action == .drawdown || $0.action == .wait } == true)
        #expect(recipe?.profileTags.contains("clean") == true)
        #expect(recipe?.authorGrinder == "Comandante C40")
    }

    @Test func theThreeScreensExistAsTypes() {
        #expect(String(describing: RecipeDetailSheet.self).isEmpty == false)
        #expect(String(describing: GuidedBrewView.self).isEmpty == false)
        #expect(String(describing: AfterBrewSheet.self).isEmpty == false)
    }
}
