import Foundation
import Vision
import os

/// Detects QR codes, Data Matrix, and barcodes on a scanned card image.
/// Runs in parallel with OCR during ingest.
nonisolated enum LabelCodeReader {
    struct Found: Sendable {
        var payload: String
        /// Normalized, origin at the bottom left.
        var bounds: CGRect
    }

    /// Scans the original capture for machine-readable codes and returns the
    /// first payload found, preferring URLs over opaque strings.
    static func read(cardID: UUID) async -> String? {
        let found = await readAll(cardID: cardID)
        let payloads = found.map(\.payload)
        if let link = payloads.first(where: { $0.hasPrefix("https://") || $0.hasPrefix("http://") }) {
            return link
        }
        return payloads.first
    }

    static func readAll(cardID: UUID) async -> [Found] {
        let url = ImageStore.shared.url(for: cardID, kind: .original)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return []
        }

        do {
            return found(in: try await request.perform(on: url))
        } catch {
            Log.app.notice("barcode detection failed: \(error)")
            return []
        }
    }

    /// The same read on a photo still in memory: a cup's card, never filed.
    static func readAll(image: CGImage) async -> [Found] {
        do {
            return found(in: try await request.perform(on: image))
        } catch {
            Log.app.notice("barcode detection failed: \(error)")
            return []
        }
    }

    private static var request: DetectBarcodesRequest {
        var request = DetectBarcodesRequest()
        request.symbologies = [.qr, .microQR, .dataMatrix, .ean13, .ean8, .code128]
        return request
    }

    private static func found(in observations: [BarcodeObservation]) -> [Found] {
        observations.compactMap { observation in
            guard let payload = observation.payloadString else { return nil }
            return Found(payload: payload, bounds: observation.boundingBox.cgRect)
        }
    }
}
