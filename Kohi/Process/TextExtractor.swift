import CoreGraphics
import Foundation
import Vision
import os

/// Reads a scanned card. Uses the document reader rather than plain text
/// recognition because cards are laid out as label/value pairs, and knowing
/// which line a value belongs to is most of the parsing problem.
nonisolated enum TextExtractor {
    /// One line of the card, in reading order.
    struct Line: Sendable {
        let text: String
        /// Vertical position, 0 at the top. Used to keep reading order stable.
        let y: Double
        let x: Double
    }

    static func read(cardID: UUID) async -> [Line] {
        // Always read the full resolution scan. Card type runs to six or seven
        // points; a thumbnail throws away exactly the detail that matters.
        let url = ImageStore.shared.url(for: cardID, kind: .flat)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return []
        }

        var request = RecognizeDocumentsRequest()
        // Card type is small relative to the card, so the default floor of 1/32
        // is too coarse.
        request.textRecognitionOptions.minimumTextHeightFraction = 1 / 64
        // Lot codes like "AA Tekangu Ngunguru #101" get "corrected" into
        // something else entirely when this is on.
        request.textRecognitionOptions.useLanguageCorrection = false
        request.textRecognitionOptions.maximumCandidateCount = 1

        do {
            let observations = try await request.perform(on: url)
            guard let document = observations.first?.document else { return [] }
            return lines(in: document)
        } catch {
            Log.app.notice("OCR failed, leaving the fields empty (\(error))")
            return []
        }
    }

    private static func lines(in container: DocumentObservation.Container) -> [Line] {
        var result: [Line] = []

        func append(_ text: DocumentObservation.Container.Text) {
            for line in text.lines {
                let value = line.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty else { continue }
                let region = line.boundingRegion.boundingBox
                result.append(
                    Line(text: value, y: 1 - Double(region.origin.y), x: Double(region.origin.x))
                )
            }
        }

        append(container.text)
        for table in container.tables {
            for row in table.rows {
                for cell in row {
                    append(cell.content.text)
                }
            }
        }

        // Reading order, tolerating small vertical jitter between columns.
        return result.sorted {
            abs($0.y - $1.y) < 0.012 ? $0.x < $1.x : $0.y < $1.y
        }
    }
}
