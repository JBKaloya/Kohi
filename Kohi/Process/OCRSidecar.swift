import CoreGraphics
import Foundation

/// Text boxes and barcode rects saved with the scan, so the stamp does not
/// run OCR again. Rects are normalized, origin at the bottom left.
nonisolated struct OCRSidecar: Codable, Sendable {
    struct Line: Codable, Sendable {
        var text: String
        var bounds: CGRect
    }

    var lines: [Line]
    var barcodes: [CGRect]

    static func write(cardID: UUID, lines: [TextExtractor.Line], barcodes: [CGRect]) {
        let sidecar = OCRSidecar(
            lines: lines.map { Line(text: $0.text, bounds: $0.bounds) },
            barcodes: barcodes
        )
        let url = CardFiles.ocrJSON(cardID)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        guard let data = try? JSONEncoder().encode(sidecar) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func load(cardID: UUID) -> OCRSidecar? {
        guard let data = try? Data(contentsOf: CardFiles.ocrJSON(cardID)) else { return nil }
        return try? JSONDecoder().decode(OCRSidecar.self, from: data)
    }

    /// The sidecar if it exists, otherwise one OCR pass written back.
    static func boxes(for cardID: UUID) async -> (text: [CGRect], barcodes: [CGRect]) {
        if let sidecar = load(cardID: cardID) {
            return (sidecar.lines.map(\.bounds), sidecar.barcodes)
        }
        let lines = await TextExtractor.read(cardID: cardID)
        let codes = await LabelCodeReader.readAll(cardID: cardID)
        write(cardID: cardID, lines: lines, barcodes: codes.map(\.bounds))
        return (lines.map(\.bounds), codes.map(\.bounds))
    }
}
