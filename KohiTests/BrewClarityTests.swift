import Foundation
import SwiftUI
import Testing
@testable import Kohi

/// The journeys that exist and must be findable: log without the timer, a
/// new recipe from Mine, Save as recipe, editing a saved brew, the kit.
@MainActor
struct BrewClarityTests {
    @Test func logElsewhereOpensTheAmountsAndBackForgetsIt() {
        let setup = BrewJourneySupport.setup()
        let session = BrewSession(card: BrewJourneySupport.card(), start: .start, setup: setup)
        session.logElsewhere()
        #expect(session.step == .dial)
        #expect(session.logsElsewhere)
        #expect(session.retreat())
        #expect(session.step == .start)
        #expect(!session.logsElsewhere)
    }

    @Test func theKitIsNoLongerAStep() throws {
        let host = try String(contentsOf: BrewJourneySupport.kohiRoot().appending(path: "Recipes/BrewFlowHost.swift"))
        #expect(!host.contains("case .kit"))
        #expect(!host.contains("BrewKitView"))
        let dial = try String(contentsOf: BrewJourneySupport.kohiRoot().appending(path: "Recipes/BrewDialView.swift"))
        #expect(dial.contains("KitSummaryRow(session: session)"))
    }

    @Test func theKitLineReadsBrewerGrinderPaper() {
        let setup = BrewJourneySupport.setup()
        let session = BrewSession(
            card: BrewJourneySupport.card(),
            recipe: ReferenceBase.recipe(referenceID: "a1-v60-ultimate"),
            start: .dial,
            setup: setup
        )
        let line = KitSummaryRow.summary(of: session.brew, in: setup)
        #expect(line?.contains("V60") == true)
        #expect(line?.contains("J-Ultra") == true)
        #expect(line?.contains(" · ") == true)
    }

    @Test func theLastKitOnThisCoffeeWinsOverTheDefault() {
        let setup = BrewJourneySupport.setup()
        let origami = Equipment(kind: .brewer, brand: "Origami", model: "Dripper S")
        setup.add(origami)
        var card = BrewJourneySupport.card(agitation: nil)
        card.brews = [Brew(method: .v60, dose: 15, water: 250, equipmentIDs: [origami.id])]
        let session = BrewSession(
            card: card,
            recipe: ReferenceBase.recipe(referenceID: "a1-v60-ultimate"),
            start: .dial,
            setup: setup
        )
        #expect(BrewKit.activeBrewer(on: session.brew, in: setup)?.id == origami.id)
    }

    @Test func withoutALastKitTheDefaultsDecide() {
        let setup = BrewJourneySupport.setup()
        let session = BrewSession(
            card: BrewJourneySupport.card(),
            recipe: ReferenceBase.recipe(referenceID: "a1-v60-ultimate"),
            start: .dial,
            setup: setup
        )
        #expect(BrewKit.activeBrewer(on: session.brew, in: setup)?.model == "V60")
    }

    @Test func aCorrectionAfterTheBrewTouchesOnlyThisBrew() {
        let setup = BrewJourneySupport.setup()
        let recipe = ReferenceBase.recipe(referenceID: "a1-v60-ultimate")
        let opened = BrewSession(card: BrewJourneySupport.card(), recipe: recipe, start: .dial, setup: setup)
        let session = BrewSession(
            card: BrewJourneySupport.card(),
            recipe: recipe,
            existing: opened.brew,
            mode: .edit,
            start: .after,
            setup: setup
        )
        let defaults = setup.defaults(for: .v60).map(\.id)
        let snapshot = session.brew.recipeSnapshot
        session.correct(family: .espresso, setup: setup)
        #expect(session.brew.method?.family == .espresso)
        #expect(session.recipe?.id == recipe?.id)
        #expect(session.brew.recipeSnapshot == snapshot)
        #expect(setup.defaults(for: .v60).map(\.id) == defaults)
    }

    @Test func theJourneysAreNamedWhereTheyHappen() throws {
        let root = BrewJourneySupport.kohiRoot()
        let start = try String(contentsOf: root.appending(path: "Recipes/BrewStartView.swift"))
        #expect(start.contains("Copy.logBrewMadeElsewhere"))
        let scope = try String(contentsOf: root.appending(path: "Recipes/BrewScopeView.swift"))
        #expect(scope.contains("Copy.newRecipe"))
        #expect(scope.contains("source = .mine"))
        let after = try String(contentsOf: root.appending(path: "Recipes/AfterBrewSheet.swift"))
        #expect(after.contains("Copy.editThisBrew"))
        #expect(after.contains("Copy.keepTheseSteps"))
        #expect(after.contains("KitSummaryRow(session: session, correcting: true)"))
        #expect(after.contains("GrindRail("))
        #expect(after.contains(".disabled(isLocked)"))
        let kit = try String(contentsOf: root.appending(path: "Recipes/BrewKitSheet.swift"))
        #expect(kit.contains("session.correct(family:"))
        #expect(kit.contains("correcting ? nil : session.recipe"))
    }

    @Test func alreadyBrewedStaysOnTheSwipeBar() throws {
        let dial = try String(contentsOf: BrewJourneySupport.kohiRoot().appending(path: "Recipes/BrewDialView.swift"))
        let bar = dial.split(separator: "private var brewBar").dropFirst().first?.prefix(700) ?? ""
        #expect(bar.contains("Copy.logWithoutTimer"))
        #expect(bar.contains("SwipeToStart"))
        #expect(bar.contains("if !session.logsElsewhere"))
    }

    @Test func skipStaysPutUnderTheCoffeeList() throws {
        let picker = try String(contentsOf: BrewJourneySupport.kohiRoot().appending(path: "Recipes/RecipeDetailSheet.swift"))
        #expect(picker.contains("skipTitle: Copy.skipCoffee"))
        #expect(picker.contains("onSkip: onSkip.map"))
        let timer = try String(contentsOf: BrewJourneySupport.kohiRoot().appending(path: "Recipes/GuidedBrewView.swift"))
        #expect(timer.contains(".background(Palette.paper.ignoresSafeArea())"))
        #expect(timer.contains(".statusBarHidden(true)"))
        #expect(timer.contains(".persistentSystemOverlays(.hidden)"))
    }

    @Test func theCopyNamesTheJourneys() {
        #expect(Copy.logWithoutTimer == "Already brewed? Log it")
        #expect(Copy.logWithoutTimerHint == "Made elsewhere or with another app: enter what you did.")
        #expect(Copy.keepTheseSteps == "Keep these steps for next time")
    }
}

/// Reproduced on the simulator: the focused time sat on the keyboard bar,
/// scrolling never closed it, the total was out of sight.
struct StepBuilderKeyboardTests {
    @Test func theStepsSheetLetsTheKeyboardGo() throws {
        let text = try String(contentsOf: BrewJourneySupport.kohiRoot().appending(path: "Recipes/StepBuilderSheet.swift"))
        #expect(text.contains(".scrollDismissesKeyboard(.interactively)"))
        #expect(text.contains("proxy.scrollTo(field, anchor: Self.focusAnchor)"))
        #expect(text.contains(".focused($focus, equals: .at(step.id))"))
        #expect(text.contains(".focused($focus, equals: .until(step.id))"))
        #expect(text.contains(".safeAreaInset(edge: .bottom"))
        #expect(text.contains("if !keyboardUp"))
        #expect(text.contains(".keyboardDoneButton()"))
    }

    @Test func theFocusedTimeLandsHigh() {
        #expect(StepBuilderSheet.focusAnchor.y < 0.5)
    }

    @Test func doneReadsAsAKey() throws {
        let text = try String(contentsOf: BrewJourneySupport.kohiRoot().appending(path: "Design/FormField.swift"))
        #expect(text.contains("KeyboardDoneKey()"))
        #expect(text.contains("frame(minWidth: 44, minHeight: 44)"))
    }
}
