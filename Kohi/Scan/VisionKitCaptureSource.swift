import os
import SwiftUI
import VisionKit

/// The system document scanner, wrapped just enough to hand back a `CapturedCard`.
///
/// This is the stand-in that got the scan loop working end to end before the
/// custom camera existed. It stays in the project as a working escape hatch: if
/// auto-capture ever misbehaves in the field, flipping `ScanSource.preferred`
/// back to `.visionKit` restores a scanner that always works.
struct VisionKitCaptureView: UIViewControllerRepresentable {
    let onCapture: (CapturedCard) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onCancel: onCancel)
    }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        private let onCapture: (CapturedCard) -> Void
        private let onCancel: () -> Void

        init(onCapture: @escaping (CapturedCard) -> Void, onCancel: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onCancel = onCancel
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            // Only the first page matters; a card has one side worth keeping.
            guard scan.pageCount > 0, let image = scan.imageOfPage(at: 0).cgImage else {
                onCancel()
                return
            }
            // VisionKit already deskewed the page, so there is no quad to apply.
            onCapture(CapturedCard(image: image, quad: nil))
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onCancel()
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: any Error
        ) {
            Log.app.error("document camera failed: \(error)")
            onCancel()
        }
    }
}
