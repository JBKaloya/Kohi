import Foundation
import Testing
@testable import Kohi

/// Recipe on 12 November: Live first, New recipe heading Mine, Adjust on any
/// recipe, and every dictation kept to learn from.
@MainActor
struct RecipeLiveTests {
    private func source(_ file: String) throws -> String {
        try String(contentsOf: BrewJourneySupport.kohiRoot().appending(path: file))
    }

    private func store() -> RecipeStore {
        RecipeStore(files: JSONFileStore(filename: "recipes-live-\(UUID().uuidString).json"))
    }

    private func words(_ list: [(Double, String)]) -> [VoiceNoteTranscriber.Phrase] {
        list.map { VoiceNoteTranscriber.Phrase(at: $0.0, text: $0.1) }
    }

    /// The mockup's brew, word by word, as Speech gives it.
    private var dictated: [VoiceNoteTranscriber.Phrase] {
        words([
            (4.0, "Bloom"), (4.4, "40"), (4.8, "grammes,"), (5.3, "je"), (5.6, "swirle."),
            (46.0, "Je"), (46.3, "verse"), (46.7, "jusqu'à"), (47.1, "150"),
            (91.0, "Deuxième"), (91.4, "versement"), (91.9, "à"), (92.2, "250,"), (92.8, "plus"), (93.1, "lent"),
            (188.0, "Ça"), (188.4, "draine"),
        ])
    }

    // MARK: - Adjust

    @Test func adjustingAProRecipeCopiesItIntoMine() throws {
        let pro = try #require(ReferenceBase.recipe(referenceID: "a1-v60-ultimate"))
        let copy = RecipeCreation.adjusting(pro)
        #expect(copy.id != pro.id)
        #expect(copy.source == .mine)
        #expect(copy.referenceID == nil)
        #expect(copy.name == pro.name)
        #expect(copy.dose == pro.dose)
        #expect(copy.water == pro.water)
        #expect(copy.notes.hasPrefix(RecipeCreation.adjustedNote(from: pro)))
        if !pro.attribution.isEmpty { #expect(copy.notes.contains(pro.attribution)) }
        #expect(!copy.steps.contains { $0.action == .rinse })
        #expect(Set(copy.steps.map(\.id)).isDisjoint(with: pro.steps.map(\.id)))
        #expect(!RecipePickerMatch.isSame(copy, pro))
        #expect(!RecipeCreation.isYours(pro))
        #expect(ReferenceBase.recipe(referenceID: "a1-v60-ultimate") == pro)
    }

    @Test func adjustingMineUpdatesItInPlace() {
        let recipes = store()
        let setup = BrewJourneySupport.setup()
        let mine = recipes.add(RecipeCreation.blank())
        #expect(RecipeCreation.isYours(mine))
        var edited = mine
        edited.dose = 18
        recipes.update(edited)
        #expect(recipes.recipes.count == 1)
        #expect(recipes.recipe(id: mine.id)?.dose == 18)

        let session = BrewSession(card: BrewJourneySupport.card(agitation: nil), setup: setup)
        session.applyCreated(recipe: edited, setup: setup)
        #expect(session.recipe?.id == mine.id)
        #expect(session.brew.dose == 18)
    }

    @Test func theScopeSavesAdjustments() throws {
        let scope = try source("Recipes/BrewScopeView.swift")
        #expect(scope.contains("RecipeCreation.adjusting(selected)"))
        #expect(scope.contains("recipes.update(edited)"))
        #expect(scope.contains("StepBuilderSheet.adjusting(draft: selected)"))
    }

    // MARK: - Live

    @Test func liveGoesToHowMuchWithoutARecipe() {
        let setup = BrewJourneySupport.setup()
        let session = BrewSession(card: BrewJourneySupport.card(agitation: nil), setup: setup)
        session.apply(recipe: RecipeCreation.blank(), setup: setup)
        session.startLive()
        #expect(session.isLive)
        #expect(session.step == .dial)
        #expect(session.recipe == nil)
        #expect(session.brew.recipeSnapshot == nil)
        #expect(session.brew.water == nil)

        session.brew.dose = nil
        session.brewNow(in: setup)
        #expect(session.step == .pour)
        #expect(session.brew.plannedSteps.isEmpty)
        #expect(session.timerRecipe(in: setup).steps.isEmpty)
    }

    @Test func backFromHowMuchLeavesLive() {
        let setup = BrewJourneySupport.setup()
        let session = BrewSession(card: BrewJourneySupport.card(), setup: setup)
        #expect(session.step == .start)
        session.startLive()
        #expect(session.retreat())
        #expect(session.step == .start)
        #expect(!session.isLive)
    }

    @Test func choosingARecipeLeavesLive() {
        let setup = BrewJourneySupport.setup()
        let session = BrewSession(card: BrewJourneySupport.card(agitation: nil), setup: setup)
        session.startLive()
        session.apply(recipe: RecipeCreation.blank(), setup: setup)
        #expect(!session.isLive)
    }

    @Test func theTimerShowsAFreeClockInLive() throws {
        let guided = try source("Recipes/GuidedBrewView.swift")
        #expect(guided.contains("if isLive, countdown == nil {"))
        #expect(guided.contains("Copy.liveNoSteps"))
        #expect(guided.contains("if isLive, voiceNote.state == .idle"))
        let host = try source("Recipes/BrewFlowHost.swift")
        #expect(host.contains("isLive: session.isLive"))
    }

    // MARK: - Steps heard

    @Test func theDictationGivesTimedSteps() {
        let steps = SpokenBrewParser.timedSteps(phrases: dictated)
        #expect(steps.map(\.at) == [4, 46, 91, 188])
        #expect(steps.map(\.action) == [.bloom, .pour, .pour, .wait])
        #expect(steps.map(\.mass) == [40, 150, 250, nil])
        #expect(steps[0].note == "swirle")
        #expect(steps[1].note.isEmpty)
        #expect(steps[2].note == "plus lent")
        #expect(steps[3].note == "Drawdown")
    }

    @Test func englishWorksToo() {
        let steps = SpokenBrewParser.timedSteps(phrases: words([
            (3, "Bloom"), (3.3, "to"), (3.6, "45"), (3.9, "grams."),
            (40, "Pour"), (40.3, "up"), (40.5, "to"), (40.8, "200,"), (41.2, "swirl."),
            (150, "It's"), (150.4, "drawing"), (150.8, "down."),
        ]))
        #expect(steps.map(\.action) == [.bloom, .pour, .wait])
        #expect(steps.map(\.mass) == [45, 200, nil])
        #expect(steps[1].agitation == .swirl)
    }

    @Test func theSplitReadsOffTheDictatedGrams() throws {
        var brew = Brew(method: .v60, dose: 15, seconds: 200)
        let heard = LiveSteps.heard(from: dictated, seconds: 200, water: nil)
        #expect(!heard.nothingHeard)
        LiveSteps.apply(heard.steps, to: &brew)
        #expect(brew.water == 250)
        #expect(brew.actualSource == .narration)
        #expect(brew.plannedSteps.isEmpty)
        let split = try #require(LiveSteps.split(of: brew, countsBloom: true))
        #expect(split.percents == [16, 44, 40])
    }

    @Test func nothingHeardKeepsOneStepForTheClock() {
        let heard = LiveSteps.heard(from: words([(2, "Euh"), (2.5, "voilà")]), seconds: 185, water: 240)
        #expect(heard.nothingHeard)
        #expect(heard.steps.count == 1)
        #expect(heard.steps[0].until == 185)
        #expect(heard.steps[0].mass == 240)
        var brew = Brew(method: .v60, dose: 15)
        LiveSteps.apply(heard.steps, to: &brew)
        #expect(brew.actualSteps.count == 1)
        #expect(brew.actualSteps[0].targetAt == 185)
    }

    @Test func afterKeepsTheTranscriptAndSaysNothingWasHeard() throws {
        let after = try source("Recipes/AfterBrewSheet.swift")
        #expect(after.contains("if session.isLive { stepsHeard } else { whatYouDid }"))
        #expect(after.contains("Copy.nothingHeard"))
        #expect(after.contains("DictationTranscript.apply(rewritten"))
        #expect(after.contains("LiveSteps.split(of: session.brew, countsBloom: countsBloom)"))
    }

    @Test func savedAsRecipeItReplaysWithTheSameSplit() throws {
        let setup = BrewJourneySupport.setup()
        let session = BrewSession(card: BrewJourneySupport.card(agitation: nil), setup: setup)
        session.startLive()
        session.brewNow(in: setup)
        var poured = session.brew
        poured.seconds = 200
        session.poured(poured)
        LiveSteps.apply(LiveSteps.heard(from: dictated, seconds: 200, water: nil).steps, to: &session.brew)

        let draft = RecipeCreation.fromLive(brew: session.brew, family: .handBrew, card: session.card)
        #expect(draft.source == .mine)
        #expect(draft.water == 250)
        #expect(draft.brewID == session.brew.id)
        #expect(PourSplit.split(of: draft, countsBloom: true)?.percents == [16, 44, 40])

        let recipes = store()
        let saved = recipes.add(draft)
        let again = BrewSession(card: session.card, setup: setup)
        again.applyCreated(recipe: saved, setup: setup)
        #expect(!again.isLive)
        again.brewNow(in: setup)
        let timer = again.timerRecipe(in: setup)
        let total = try #require(timer.water)
        #expect(PourSplit.split(steps: timer.steps, total: total, countsBloom: true)?.percents == [16, 44, 40])
    }

    // MARK: - Archive

    private func archive() -> DictationArchive {
        DictationArchive(directory: FileManager.default.temporaryDirectory
            .appending(path: "dictations-\(UUID().uuidString)", directoryHint: .isDirectory))
    }

    private func audio() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "dictation-\(UUID().uuidString).m4a")
        try Data([0, 1, 2, 3]).write(to: url)
        return url
    }

    private var outcome: VoiceNoteTranscriber.Outcome {
        VoiceNoteTranscriber.Outcome(text: "Bloom 40 grammes", coveredThrough: 5, duration: 6, phrases: dictated)
    }

    @Test func sharingOffWritesNothing() throws {
        let archive = archive()
        #expect(archive.stash(audio: try audio(), sharing: false) == nil)
        #expect(archive.pending().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: archive.directory.path))
    }

    @Test func aDictationIsKeptUntilItIsSent() throws {
        let archive = archive()
        var changes = 0
        archive.onChange = { changes += 1 }
        let brewID = UUID()
        let id = try #require(archive.stash(audio: try audio(), sharing: true))
        #expect(FileManager.default.fileExists(atPath: archive.audioURL(id).path))
        archive.record(
            id: id,
            outcome: outcome,
            context: .live,
            brewID: brewID,
            recipeID: nil,
            parsed: DictationRecord.Parsed(steps: SpokenBrewParser.timedSteps(phrases: dictated))
        )
        #expect(changes == 1)
        let record = try #require(archive.pending().first)
        #expect(record.id == id)
        #expect(record.context == .live)
        #expect(record.parsed.steps.count == 4)
        #expect(record.phrases.count == dictated.count)

        archive.markAudioUploaded(id)
        #expect(!FileManager.default.fileExists(atPath: archive.audioURL(id).path))
        archive.markRowSent(id)
        #expect(!archive.isFinished(try #require(archive.pending().first)))

        archive.keep(editedSteps: [SpokenBrewParser.TimedStep(at: 4, action: .bloom, mass: 45)], brewID: brewID)
        let edited = try #require(archive.pending().first)
        #expect(edited.editsPending)
        #expect(edited.editedSteps?.first?.mass == 45)
        archive.markEditsSent(id)
        archive.removeFinished()
        #expect(archive.pending().isEmpty)
    }

    @Test func aSentDictationWaitsAWeekForTheKeptSteps() throws {
        let archive = archive()
        let id = try #require(archive.stash(audio: try audio(), sharing: true))
        archive.record(id: id, outcome: outcome, context: .afterBrew, brewID: nil, recipeID: nil, parsed: .init())
        archive.markAudioUploaded(id)
        archive.markRowSent(id)
        let record = try #require(archive.pending().first)
        #expect(!archive.isFinished(record))
        #expect(archive.isFinished(record, now: record.createdAt.addingTimeInterval(DictationArchive.editsWindow + 1)))
    }

    @Test func theRowUsesTheTableColumns() throws {
        let userID = UUID()
        let record = DictationRecord(
            id: UUID(),
            brewID: UUID(),
            recipeID: nil,
            context: .afterBrew,
            duration: 6,
            transcript: "Bloom 40",
            phrases: [.init(at: 4, text: "Bloom")],
            parsed: .init(steps: [SpokenBrewParser.TimedStep(at: 4, action: .bloom, mass: 40)]),
            appBuild: "1.0 (16)",
            createdAt: .now
        )
        let data = try JSONEncoder().encode(DictationRow(record: record, userID: userID))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        for key in ["id", "user_id", "brew_id", "context", "audio_path", "duration_s", "transcript",
                    "phrases", "parsed", "steps_heard", "brew_context", "app_build", "created_at"] {
            #expect(object[key] != nil, "missing \(key)")
        }
        #expect(object["context"] as? String == "after_brew")
        #expect(object["steps_heard"] as? Int == 1)
        #expect((object["audio_path"] as? String)?.hasPrefix(userID.uuidString.lowercased() + "/") == true)
    }

    @Test func sharingIsOnByDefault() throws {
        let defaults = try #require(UserDefaults(suiteName: "kohi-live-\(UUID().uuidString)"))
        let flags = LotFlags(defaults: defaults)
        #expect(flags.isOn(.shareDictations))
        #expect(!flags.isOn(.keepVoiceNote))
        #expect(LotFlags.Feature.shareDictations.label == Copy.shareDictations)
    }

    @Test func everyDictationPathGoesThroughTheArchive() throws {
        let after = try source("Recipes/AfterBrewSheet.swift")
        #expect(after.contains("DictationArchive.shared.stash(audio: url, sharing: sharing)"))
        #expect(after.contains("DictationArchive.shared.record("))
        #expect(after.contains("DictationArchive.shared.keep("))
        let root = try source("App/RootView.swift")
        #expect(root.contains("DictationArchive.shared.stash(audio: url, sharing: sharing)"))
        #expect(root.contains("sync.attach(dictations: .shared)"))
        let sync = try source("Sync/SyncCoordinator.swift")
        #expect(sync.contains("await syncDictations(client: client, userID: userID)"))
    }

    @Test func theMigrationKeepsDictationsPrivate() throws {
        let url = BrewJourneySupport.kohiRoot().deletingLastPathComponent()
            .appending(path: "supabase/migrations/0034_dictations.sql")
        let sql = try String(contentsOf: url)
        #expect(sql.contains("values ('dictations', 'dictations', false)"))
        #expect(sql.contains("create table if not exists public.dictations"))
        #expect(sql.contains("alter table public.dictations enable row level security"))
        for column in ["audio_path", "phrases", "parsed", "steps_heard", "edited_steps", "app_build"] {
            #expect(sql.contains(column))
        }
    }
}
