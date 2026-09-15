import CoreGraphics
import os
import PhotosUI
import SwiftUI
import Vision

/// Brings a photo from the library into the same review-and-ingest path as a
/// live capture: detect corners if possible, then let you adjust them.
nonisolated enum PhotoImport {
    static func load(_ item: PhotosPickerItem) async -> CapturedCard? {
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            Log.app.notice("photo import: could not read the picker item")
            return nil
        }
        // Decoding a full-resolution still and segmenting it are both slow, and
        // a nonisolated async call would run them on whichever actor asked. The
        // caller is the camera view, so that would be the main thread.
        return await Task.detached(priority: .userInitiated) {
            guard let image = ImageCodec.decodeOriented(data) else {
                Log.app.notice("photo import: could not decode the image")
                return nil
            }
            let quad = await detectQuad(in: image)
            return CapturedCard(image: image, quad: quad)
        }.value
    }

    /// One pass of the same detector the live camera uses, so library imports
    /// start with corners on the card when Vision can see one.
    static func detectQuad(in image: CGImage) async -> Quad? {
        let size = CGSize(width: image.width, height: image.height)
        let handler = ImageRequestHandler(image)
        let request = DetectDocumentSegmentationRequest()

        do {
            guard
                let observation = try await handler.perform(request),
                observation.confidence >= ScanTuning.minimumConfidence
            else { return nil }

            return Quad(
                topLeft: observation.topLeft.toImageCoordinates(size, origin: .upperLeft),
                topRight: observation.topRight.toImageCoordinates(size, origin: .upperLeft),
                bottomRight: observation.bottomRight.toImageCoordinates(size, origin: .upperLeft),
                bottomLeft: observation.bottomLeft.toImageCoordinates(size, origin: .upperLeft)
            )
        } catch {
            Log.app.notice("photo import: no document detected (\(error))")
            return nil
        }
    }
}

