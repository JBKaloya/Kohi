import Foundation
import Testing
@testable import Kohi

/// Reading a card again with its pages: what is proposed, what is left alone,
/// and what taking a proposal writes.
struct PageRereadTests {
    /// The DR Congo Majirane card as the first scan left it on 22 Nov 2026.
    private var scanned: CoffeeCard {
        CoffeeCard(
            name: "SUPER",
            roaster: "Process Coffee",
            country: "Congo",
            process: "175C",
            tastingNotes: ["NOTES"]
        )
    }

    /// What the vision model reads off the card and its label together.
    private var reading: ParsedFields {
        var fields = ParsedFields()
        fields.name = "Majirane"
        fields.roaster = "PROCESS COFFEE"
        fields.country = "Congo"
        fields.producer = "Smallholders"
        fields.altitude = "1750 masl"
        fields.process = "Washed"
        fields.tastingNotes = ["Plum", "Molasses", "Liquorice"]
        return fields
    }

    @Test func eachFieldReadDifferentlyIsProposed() {
        let proposals = PageReread.proposals(card: scanned, reading: reading)
        #expect(proposals.map(\.key) == ["name", "producer", "altitude", "process", "notes"])
        #expect(proposals.first { $0.key == "process" } == .init(key: "process", current: "175C", proposed: "Washed"))
        #expect(proposals.first { $0.key == "producer" }?.current == nil)
        #expect(proposals.first { $0.key == "notes" } == .init(key: "notes", current: "NOTES", proposed: "Plum, Molasses, Liquorice"))
    }

    @Test func theSameValueWrittenAnotherWayIsNotADifference() {
        #expect(PageReread.same("PROCESS  COFFEE", "Process Coffee"))
        #expect(PageReread.same("Café", "cafe"))
        #expect(PageReread.same("Plum|Molasses", "molasses|plum", notes: true))
        #expect(!PageReread.same("Plum|Molasses", "Plum", notes: true))
    }

    @Test func anEmptyReadingNeverClearsAField() {
        #expect(PageReread.proposals(card: scanned, reading: ParsedFields()).isEmpty)
    }

    @Test func takingProposalsWritesOnlyThoseFields() {
        let proposals = PageReread.proposals(card: scanned, reading: reading)
        let taken = proposals.filter { $0.key == "process" || $0.key == "notes" }
        let card = PageReread.apply(taken, from: reading, to: scanned)
        #expect(card.process == "Washed")
        #expect(card.tastingNotes == ["Plum", "Molasses", "Liquorice"])
        #expect(card.name == "SUPER")
        #expect(card.altitude == "")
    }

    @Test func theCardIsReadWithItsPagesAndBagSidesOldestFirst() {
        let receipt = CardAttachment(role: .receipt)
        let first = CardAttachment(role: .page)
        let bag = CardAttachment(role: .bag)
        let newest = CardAttachment(role: .page)
        let extra = CardAttachment(role: .page)
        // Attachments are kept newest first.
        let card = CoffeeCard(attachments: [extra, newest, bag, receipt, first])
        #expect(PageReread.pages(of: card) == [first.id, bag.id, newest.id])
    }

    @Test func thePayloadCarriesEveryPhotoAndTheCardAloneForOlderFunctions() {
        let payload = CardVision.payload([Data([1]), Data([2])])
        #expect(payload.images.map(\.image) == [Data([1]).base64EncodedString(), Data([2]).base64EncodedString()])
        #expect(payload.image == Data([1]).base64EncodedString())
    }
}
