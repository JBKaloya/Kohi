import CoreGraphics
import CoreImage
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

    /// Languages the reader is told to expect. Cards in this archive are
    /// English, French, Japanese, and Chinese; automatic detection picks
    /// between them per image.
    private static let languages = ["en-US", "fr-FR", "ja-JP", "zh-Hans", "zh-Hant"]

    /// Below this many lines the read probably failed for a fixable reason
    /// (card photographed sideways), so it is worth retrying rotated.
    private static let rotationRetryFloor = 4

    static func read(cardID: UUID) async -> [Line] {
        let url = ImageStore.shared.url(for: cardID, kind: .flat)
        return await readFromURL(url)
    }

    /// Reads text from an arbitrary image URL. Used for both the main card
    /// and attachment pages. If the straight read finds almost nothing, the
    /// image is retried at 90° and 270°: several archive cards were shot
    /// sideways, and Vision does not rotate on its own past small skews.
    static func readFromURL(_ url: URL) async -> [Line] {
        guard let image = ImageCodec.decode(url) else { return [] }

        var best = await read(image)
        guard best.count < rotationRetryFloor else { return best }

        for orientation in [CGImagePropertyOrientation.right, .left] {
            guard let rotated = rotate(image, orientation) else { continue }
            let lines = await read(rotated)
            if lines.count > best.count { best = lines }
        }
        return best
    }

    private static func read(_ image: CGImage) async -> [Line] {
        if #available(iOS 26, *) {
            return await readWithDocumentRequest(image: image)
        } else {
            return await readWithVNRecognizeText(image: image)
        }
    }

    private static func rotate(
        _ image: CGImage, _ orientation: CGImagePropertyOrientation
    ) -> CGImage? {
        let oriented = CIImage(cgImage: image).oriented(orientation)
        return ImagePipeline.context.createCGImage(oriented, from: oriented.extent)
    }

    // MARK: - iOS 26+ (RecognizeDocumentsRequest)

    @available(iOS 26, *)
    private static func readWithDocumentRequest(image: CGImage) async -> [Line] {
        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.minimumTextHeightFraction = 1 / 64
        request.textRecognitionOptions.useLanguageCorrection = false
        request.textRecognitionOptions.maximumCandidateCount = 1
        request.textRecognitionOptions.automaticallyDetectLanguage = true
        request.textRecognitionOptions.recognitionLanguages =
            languages.map { Locale.Language(identifier: $0) }

        do {
            let observations = try await request.perform(on: image)
            guard let document = observations.first?.document else { return [] }
            return lines(in: document)
        } catch {
            Log.app.notice("OCR failed, leaving the fields empty (\(error))")
            return []
        }
    }

    @available(iOS 26, *)
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

        return result.sorted {
            abs($0.y - $1.y) < 0.012 ? $0.x < $1.x : $0.y < $1.y
        }
    }

    // MARK: - iOS 18 fallback (VNRecognizeTextRequest)

    private static func readWithVNRecognizeText(image: CGImage) async -> [Line] {
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                guard error == nil,
                      let observations = request.results as? [VNRecognizedTextObservation]
                else {
                    continuation.resume(returning: [])
                    return
                }

                var lines: [Line] = []
                for observation in observations {
                    guard let candidate = observation.topCandidates(1).first else { continue }
                    let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { continue }
                    let box = observation.boundingBox
                    lines.append(Line(text: text, y: 1 - Double(box.origin.y), x: Double(box.origin.x)))
                }

                let sorted = lines.sorted {
                    abs($0.y - $1.y) < 0.012 ? $0.x < $1.x : $0.y < $1.y
                }
                continuation.resume(returning: sorted)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.automaticallyDetectsLanguage = true
            request.recognitionLanguages = languages

            let handler = VNImageRequestHandler(cgImage: image)
            do {
                try handler.perform([request])
            } catch {
                Log.app.notice("OCR failed, leaving the fields empty (\(error))")
                continuation.resume(returning: [])
            }
        }
    }
}
