import Foundation
import Testing
@testable import Kohi

struct TranscriptChunksTests {
    private typealias Segment = TranscriptChunks.Segment

    private func words(_ text: String, from start: TimeInterval, step: TimeInterval = 0.4) -> [Segment] {
        text.split(separator: " ").enumerated().map { index, word in
            Segment(at: start + Double(index) * step, duration: step * 0.8, text: String(word))
        }
    }

    @Test func aRecognizerThatStartsOverAfterAPauseKeepsEveryChunk() {
        var chunks = TranscriptChunks()
        chunks.feed(words("Je fais", from: 3))
        chunks.feed(words("Je fais un bloom de 40 grammes.", from: 3), endsUtterance: true)
        chunks.feed(words("Je verse", from: 20))
        chunks.feed(words("Je verse jusqu'à 150 grammes.", from: 20))
        chunks.feed(words("Et enfin", from: 80))
        chunks.feed(words("Et enfin je termine.", from: 80))
        #expect(chunks.text == "Je fais un bloom de 40 grammes. Je verse jusqu'à 150 grammes. Et enfin je termine.")
        #expect(chunks.segments.first?.at == 3)
        #expect(chunks.end > 80)
    }

    @Test func aCumulativeResultIsNotRepeated() {
        var chunks = TranscriptChunks()
        chunks.feed(words("Je fais un bloom.", from: 3), endsUtterance: true)
        chunks.feed(words("Je verse.", from: 20), endsUtterance: true)
        chunks.feed(words("Je fais un bloom. Je verse. Et enfin je termine.", from: 3))
        #expect(chunks.text == "Je fais un bloom. Je verse. Et enfin je termine.")
    }

    @Test func revisionsInsideAChunkReplaceIt() {
        var chunks = TranscriptChunks()
        chunks.feed(words("Je verse jusque", from: 20))
        chunks.feed(words("Je verse jusqu'à 150", from: 20))
        #expect(chunks.text == "Je verse jusqu'à 150")
    }

    @Test func partialsWithoutTimesStillSettleOnAFreshStart() {
        var chunks = TranscriptChunks()
        let untimed: (String) -> [Segment] = { text in
            text.split(separator: " ").map { Segment(at: 0, duration: 0, text: String($0)) }
        }
        chunks.feed(untimed("Je fais un bloom de 40 grammes"))
        chunks.feed(untimed("Et enfin"))
        #expect(chunks.text == "Je fais un bloom de 40 grammes Et enfin")
    }

    @Test func theSettledPhrasesGiveTheTimedSteps() {
        var chunks = TranscriptChunks()
        chunks.feed(words("Bloom 40 grammes.", from: 3), endsUtterance: true)
        chunks.feed(words("Verse jusqu'à 150.", from: 20), endsUtterance: true)
        chunks.feed(words("Verse jusqu'à 250.", from: 40))
        let phrases = chunks.segments.map { VoiceNoteTranscriber.Phrase(at: $0.at, text: $0.text) }
        let steps = SpokenBrewParser.timedSteps(phrases: phrases)
        #expect(steps.map(\.mass) == [40, 150, 250])
        #expect(steps.map(\.at) == [3, 20, 40])
    }
}
