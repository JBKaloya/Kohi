import Foundation
import Testing

@testable import Kohi

/// Build 14: On the pack as chips with wheel suggestions, and the notes kept
/// consistent from the entry to the card.

struct PackNotesTests {
    @Test func theWheelAnswersInEnglishFrenchAndSynonyms() {
        #expect(FlavorSuggestions.suggest("pea").contains("Peach"))
        #expect(FlavorSuggestions.suggest("pêch").contains("Peach"))
        #expect(FlavorSuggestions.suggest("peche").contains("Peach"))
        #expect(FlavorSuggestions.suggest("citron").contains("Lemon"))
        #expect(FlavorSuggestions.suggest("jasm").first == "Jasmine")
    }

    @Test func oneLetterOffersNothingAndTakenNotesAreHidden() {
        #expect(FlavorSuggestions.suggest("p").isEmpty)
        #expect(!FlavorSuggestions.suggest("pea", excluding: ["peach"]).contains("Peach"))
        #expect(FlavorSuggestions.suggest("pea", limit: 2).count <= 2)
    }

    @Test func aCommaTurnsTheEntryIntoChips() {
        var draft = TastingDraft()
        draft.notesEntry = "Passion fruit, lemon candy,"
        draft.commitNotesEntry()
        #expect(draft.coffee.tastingNotes == ["Passion fruit", "lemon candy"])
        #expect(draft.notesEntry.isEmpty)
    }

    @Test func spacesAndCommasAreNoLongerSwallowed() {
        var draft = TastingDraft()
        draft.notesEntry = "White wine"
        #expect(draft.notesEntry == "White wine")
        draft.commitNotesEntry()
        #expect(draft.coffee.tastingNotes == ["White wine"])
    }

    @Test func aDuplicateIsDroppedWhateverItsCase() {
        var draft = TastingDraft()
        draft.addNote("Peach")
        draft.addNote("peach")
        draft.addNote("  ")
        #expect(draft.coffee.tastingNotes == ["Peach"])
    }

    @Test func aSuggestionReplacesWhatWasTyped() {
        var draft = TastingDraft()
        draft.notesEntry = "pêch"
        draft.pick(suggestion: "Peach")
        #expect(draft.coffee.tastingNotes == ["Peach"])
        #expect(draft.notesEntry.isEmpty)
    }

    @Test func whatIsLeftInTheEntryIsSaved() {
        var draft = TastingDraft()
        draft.coffee.name = "Bulga"
        draft.addNote("Peach")
        draft.notesEntry = "Dragon fruit"
        #expect(draft.hasContent)
        #expect(draft.tasting(base: nil).coffee.tastingNotes == ["Peach", "Dragon fruit"])
    }

    @Test func removingAChipRemovesTheNote() {
        var draft = TastingDraft()
        draft.addNote("Peach")
        draft.addNote("Lemon")
        draft.removeNote("Peach")
        #expect(draft.coffee.tastingNotes == ["Lemon"])
    }

    @Test func theFieldIsChipsWithoutDictation() throws {
        let fields = try String(
            contentsOf: DevBrief10.kohiRoot.appending(path: "Tastings/TastingFields.swift"),
            encoding: .utf8
        )
        #expect(fields.contains("TastingNotesField(draft: $draft)"))
        #expect(!fields.contains("TastingTextField(label: Copy.onThePack"))
        let start = try #require(fields.range(of: "struct TastingNotesField"))
        let end = try #require(fields.range(of: "struct TastingRoasterField"))
        let body = fields[start.lowerBound..<end.lowerBound]
        #expect(body.contains("FlavorSuggestions.suggest"))
        #expect(body.contains("showsRemove: true"))
        #expect(!body.contains("DictationField"))
    }
}

struct NotesCoherenceTests {
    @Test func packNotesBecomeDeclaredChipsInTheTasting() {
        var draft = TastingDraft()
        draft.notesEntry = "Peach, Jasmine, Passion fruit"
        draft.commitNotesEntry()
        let declared = draft.coffee.declaredFlavors.map(\.id)
        #expect(declared == ["fruity-other-fruit-peach", "floral-floral-jasmine"])
    }

    @Test func linkingACardCopiesItsNotes() {
        var card = CoffeeCard(name: "Bulga West Arsi")
        card.tastingNotes = ["Passion fruit", "Lemon candy"]
        var draft = TastingDraft()
        draft.coffee.name = "typed"
        draft.link(card)
        #expect(draft.coffee.tastingNotes == ["Passion fruit", "Lemon candy"])
    }

    @Test func aScanFillsNotesOnlyWhenEmpty() {
        var parsed = ParsedFields()
        parsed.tastingNotes = ["Passion fruit", "White wine"]

        var empty = TastingDraft()
        empty.fill(from: parsed)
        #expect(empty.coffee.tastingNotes == ["Passion fruit", "White wine"])

        var typed = TastingDraft()
        typed.addNote("Peach")
        typed.fill(from: parsed)
        #expect(typed.coffee.tastingNotes == ["Peach"])
    }

    @Test func aMenuLineStillWritesTheNotes() {
        var draft = TastingDraft()
        draft.notesText = "Peach, Lemon"
        #expect(draft.coffee.tastingNotes == ["Peach", "Lemon"])
    }

    @Test func dictatedNotesOnTheCardStillCommitOnReturn() throws {
        let tagField = try String(
            contentsOf: DevBrief10.kohiRoot.appending(path: "Edit/TagField.swift"),
            encoding: .utf8
        )
        #expect(tagField.contains("DictationField(text: $entry"))
        #expect(tagField.contains("if value.contains(\"\\n\") { commit() }"))
    }

    @Test func savedNotesSurviveTheRow() {
        var draft = TastingDraft()
        draft.coffee.name = "Bulga"
        draft.notesEntry = "Passion fruit, Lemon candy"
        let saved = draft.tasting(base: nil)
        let row = TastingRow(tasting: saved, userID: UUID())
        #expect(row.toTasting().coffee.tastingNotes == ["Passion fruit", "Lemon candy"])
        #expect(TastingDraft(row.toTasting()).coffee.tastingNotes == ["Passion fruit", "Lemon candy"])
    }
}
