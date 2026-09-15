import Foundation
import Vision
import os

/// Detects QR codes, Data Matrix, and barcodes on a scanned card image.
/// Runs in parallel with OCR during ingest.
nonisolated enum LabelCodeReader {
    /// Scans the original capture for machine-readable codes and returns the
    /// first payload found, preferring URLs over opaque strings.
    static func read(cardID: UUID) async -> String? {
        let url = ImageStore.shared.url(for: cardID, kind: .original)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return nil
        }

        do {
            var request = DetectBarcodesRequest()
            request.symbologies = [.qr, .microQR, .dataMatrix, .ean13, .ean8, .code128]
            let observations = try await request.perform(on: url)

            let payloads = observations.compactMap(\.payloadString)
            // Prefer an https URL over a raw code.
            if let link = payloads.first(where: { $0.hasPrefix("https://") || $0.hasPrefix("http://") }) {
                return link
            }
            return payloads.first
        } catch {
            Log.app.notice("barcode detection failed: \(error)")
            return nil
        }
    }
}
