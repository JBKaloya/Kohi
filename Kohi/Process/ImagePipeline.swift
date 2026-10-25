import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreVideo
import Foundation
import os
import Vision

nonisolated enum IngestError: Error {
    case encodingFailed
}

/// Turns what is on disk into something drawable. Everything here runs off the
/// main actor and never touches SwiftUI.
nonisolated enum ImagePipeline {
    /// One shared context. Creating these per call is the classic way to make an
    /// image pipeline slow.
    static let context = CIContext(options: [.cacheIntermediates: false])

    /// How much of the deskewed frame the cut-out mask has to cover to be
    /// believed. Below this the subject lift found something other than the card;
    /// above it, it found everything and has told us nothing.
    static let plausibleMaskCoverage: ClosedRange<Double> = 0.60...0.995

    /// How hard the document enhancer works. The filter runs 0 to 10; past about
    /// 2 a dark or saturated card stock starts to blow out.
    static let enhanceAmount: Float = 1.0

    /// Takes a confirmed scan, writes the archival files, and returns the card
    /// record that points at them. Runs off the main actor.
    static func ingest(_ scan: ScanResult) async throws -> CoffeeCard {
        let id = UUID()

        guard let originalData = ImageCodec.encodeHEIC(scan.image, quality: 0.92) else {
            throw IngestError.encodingFailed
        }
        try ImageStore.shared.write(originalData, for: id, kind: .original)

        let deskewed = correctPerspective(scan.image, quad: scan.quad) ?? scan.image

        // The cut-out runs on the deskewed card before any enhancement, so the
        // segmenter sees the same image it always has and the coverage range
        // above still means what it did. Whitening the background first would
        // quietly move that goalpost.
        var hasMask = false
        if let mask = await makeCutoutMask(for: deskewed),
           let maskData = ImageCodec.encodePNG(mask) {
            try? ImageStore.shared.write(maskData, for: id, kind: .mask)
            hasMask = true
        }

        let flat = scan.enhance ? (enhance(deskewed) ?? deskewed) : deskewed
        guard let flatData = ImageCodec.encodeHEIC(flat, quality: 0.9) else {
            throw IngestError.encodingFailed
        }
        try ImageStore.shared.write(flatData, for: id, kind: .flat)

        let now = Date.now
        return CoffeeCard(
            id: id,
            date: now,
            createdAt: now,
            updatedAt: now,
            aspectRatio: Double(flat.width) / Double(flat.height),
            hasMask: hasMask,
            enhanced: scan.enhance
        )
    }

    /// Lightweight ingest for an attachment: deskew + enhance, write the flat
    /// image into the parent card's directory. No mask, no original kept.
    static func ingestAttachment(
        _ scan: ScanResult,
        cardID: UUID
    ) async throws -> CardAttachment {
        let attachID = UUID()

        let deskewed = correctPerspective(scan.image, quad: scan.quad) ?? scan.image
        let flat = scan.enhance ? (enhance(deskewed) ?? deskewed) : deskewed

        guard let data = ImageCodec.encodeHEIC(flat, quality: 0.9) else {
            throw IngestError.encodingFailed
        }
        try ImageStore.shared.write(data, for: cardID, kind: .attachment(attachID))

        return CardAttachment(
            id: attachID,
            role: .page,
            aspectRatio: Double(flat.width) / Double(flat.height)
        )
    }

    /// Renders and caches a thumbnail for an attachment.
    static func makeAttachmentThumbnail(
        cardID: UUID, attachmentID: UUID, bucket: Int
    ) -> CGImage? {
        let url = ImageStore.shared.url(for: cardID, kind: .attachment(attachmentID))
        guard let image = ImageCodec.downsample(url, maxPixel: bucket) else { return nil }
        if let data = ImageCodec.encodeHEIC(image, quality: 0.85) {
            try? ImageStore.shared.write(data, for: cardID, kind: .attachmentThumbnail(attachmentID, bucket))
        }
        return image
    }

    /// Scales an in-memory image down to fit `maxPixel` on its longest edge.
    /// Used to get a full still down to something the review screen can filter
    /// and redraw without stuttering.
    static func downsample(_ image: CGImage, maxPixel: Int) -> CGImage? {
        let longest = CGFloat(max(image.width, image.height))
        guard longest > CGFloat(maxPixel) else { return image }
        let factor = CGFloat(maxPixel) / longest
        let scaled = CIImage(cgImage: image)
            .transformed(by: CGAffineTransform(scaleX: factor, y: factor))
        return context.createCGImage(scaled, from: scaled.extent)
    }

    /// The scan look: shadows lifted, background whitened, contrast opened up.
    /// `CIDocumentEnhancer` is the filter behind the system scanner, and it
    /// works in colour, so a card printed on kraft or navy stays that colour.
    static func enhance(_ image: CGImage, amount: Float = enhanceAmount) -> CGImage? {
        let filter = CIFilter.documentEnhancer()
        filter.inputImage = CIImage(cgImage: image)
        filter.amount = amount
        guard let output = filter.outputImage else { return nil }
        return context.createCGImage(output, from: output.extent)
    }

    /// Lifts the card off whatever is left of the background. Returns nil rather
    /// than a bad mask: a plain rectangle looks fine, a wrong cut-out does not.
    static func makeCutoutMask(for image: CGImage) async -> CGImage? {
        let handler = ImageRequestHandler(image)

        let observation: InstanceMaskObservation?
        do {
            observation = try await handler.perform(GenerateForegroundInstanceMaskRequest())
        } catch {
            Log.app.notice("cut-out: request failed, keeping the plain rectangle (\(error))")
            return nil
        }

        guard let observation, !observation.allInstances.isEmpty else {
            Log.app.notice("cut-out: no subject found, keeping the plain rectangle")
            return nil
        }

        guard let buffer = try? observation.generateScaledMask(
            for: observation.allInstances, scaledToImageFrom: handler
        ) else {
            Log.app.notice("cut-out: mask could not be scaled, keeping the plain rectangle")
            return nil
        }

        let mask = CIImage(cvPixelBuffer: buffer)
        let fraction = coverage(of: mask)
        guard plausibleMaskCoverage.contains(fraction) else {
            // Expected for a well deskewed card: the crop already removed the
            // background, so the subject is the entire frame.
            Log.app.notice("cut-out: mask covers \(fraction) of the frame, not plausible")
            return nil
        }
        Log.app.notice("cut-out: mask covers \(fraction) of the frame, applied")
        return context.createCGImage(mask, from: mask.extent)
    }

    /// Mean value of a single channel mask, which for a 0/1 mask is the fraction
    /// of the frame it covers.
    private static func coverage(of mask: CIImage) -> Double {
        let average = CIFilter.areaAverage()
        average.inputImage = mask
        average.extent = mask.extent
        guard let output = average.outputImage else { return 0 }

        var pixel = [Float](repeating: 0, count: 4)
        context.render(
            output,
            toBitmap: &pixel,
            rowBytes: 4 * MemoryLayout<Float>.size,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBAf,
            colorSpace: nil
        )
        return Double(pixel[0])
    }

    /// Deskews the card to a flat rectangle. Core Image works from a bottom-left
    /// origin, so the quad's y coordinates are flipped on the way in.
    static func correctPerspective(_ image: CGImage, quad: Quad) -> CGImage? {
        let source = CIImage(cgImage: image)
        let height = CGFloat(image.height)
        func flip(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x, y: height - point.y)
        }

        let filter = CIFilter.perspectiveCorrection()
        filter.inputImage = source
        filter.topLeft = flip(quad.topLeft)
        filter.topRight = flip(quad.topRight)
        filter.bottomRight = flip(quad.bottomRight)
        filter.bottomLeft = flip(quad.bottomLeft)
        filter.crop = true

        guard let output = filter.outputImage else { return nil }
        return context.createCGImage(output, from: output.extent)
    }

    /// The archival image for a card, with the cut-out mask applied when there is
    /// one. `maxPixel` bounds the longest edge; pass nil for full resolution.
    static func composed(id: UUID, hasMask: Bool, maxPixel: Int? = nil) -> CGImage? {
        let store = ImageStore.shared
        let flatURL = store.url(for: id, kind: .flat)

        // Fast path: no mask means Image I/O can decode straight to the size we
        // need without Core Image ever getting involved.
        guard hasMask, store.exists(id, kind: .mask) else {
            if let maxPixel {
                return ImageCodec.downsample(flatURL, maxPixel: maxPixel)
            }
            return ImageCodec.decode(flatURL)
        }

        guard
            let flat = CIImage(contentsOf: flatURL),
            let mask = CIImage(contentsOf: store.url(for: id, kind: .mask))
        else { return ImageCodec.decode(flatURL) }

        let scaledMask = mask.transformed(
            by: scaleTransform(from: mask.extent.size, to: flat.extent.size)
        )

        // Smooth the mask boundary then feather it. A morphological close
        // (dilate → erode) fills small gaps from wrinkled packaging, then
        // an extra erode pulls in fringe pixels and a blur softens the edge.
        let longest = max(flat.extent.width, flat.extent.height)
        let closeRadius = max(1, longest * 0.003)
        let closed = scaledMask
            .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: closeRadius])
            .applyingFilter("CIMorphologyMinimum", parameters: [kCIInputRadiusKey: closeRadius])
        let eroded = closed.applyingFilter("CIMorphologyMinimum", parameters: [
            kCIInputRadiusKey: max(1, longest * 0.003),
        ])
        let softMask = eroded
            .clampedToExtent()
            .applyingGaussianBlur(sigma: max(1, longest * 0.006))
            .cropped(to: scaledMask.extent)

        let cutout = flat.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: CIImage.empty(),
            kCIInputMaskImageKey: softMask,
        ])

        let scaled: CIImage
        if let maxPixel {
            let longest = max(cutout.extent.width, cutout.extent.height)
            let factor = min(1, CGFloat(maxPixel) / longest)
            scaled = factor < 1
                ? cutout.transformed(by: CGAffineTransform(scaleX: factor, y: factor))
                : cutout
        } else {
            scaled = cutout
        }

        return context.createCGImage(scaled, from: scaled.extent)
    }

    private static func scaleTransform(from: CGSize, to: CGSize) -> CGAffineTransform {
        guard from.width > 0, from.height > 0 else { return .identity }
        return CGAffineTransform(scaleX: to.width / from.width, y: to.height / from.height)
    }

    /// Renders and caches a thumbnail file for one bucket, returning the image.
    static func makeThumbnail(id: UUID, hasMask: Bool, bucket: Int) -> CGImage? {
        guard let image = composed(id: id, hasMask: hasMask, maxPixel: bucket) else { return nil }
        if let data = ImageCodec.encodeHEIC(image, quality: 0.85) {
            try? ImageStore.shared.write(data, for: id, kind: .thumbnail(bucket))
        }
        return image
    }
}
