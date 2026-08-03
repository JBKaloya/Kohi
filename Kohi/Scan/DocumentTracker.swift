import CoreImage
import CoreImage.CIFilterBuiltins
import CoreMedia
import CoreVideo
import Foundation
import Vision

/// Runs document segmentation on the video feed and decides, frame by frame,
/// whether the card is worth capturing yet.
///
/// Everything the coaching layer needs is derived from the quad the detector
/// already returns, plus one cheap histogram for glare. No extra frameworks and
/// no second model.
nonisolated final class DocumentTracker: @unchecked Sendable {
    struct Detection: Sendable {
        /// Corners in frame pixel coordinates, top-left origin.
        let quad: Quad
        let frameSize: CGSize
        let coaching: CoachingState
        /// True on the frame where the lock completes.
        let shouldCapture: Bool
    }

    private let request = DetectDocumentSegmentationRequest()
    private var recent: [Quad] = []
    private var smoothed: Quad?
    private var steadySince: Date?
    private var frameIndex = 0
    private var lastGlare = false

    func reset() {
        recent.removeAll()
        smoothed = nil
        steadySince = nil
        lastGlare = false
    }

    func analyze(_ frame: VideoFrame) async -> Detection? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(frame.sampleBuffer) else { return nil }
        let frameSize = CGSize(
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer)
        )

        frameIndex &+= 1

        guard
            let observation = try? await request.perform(on: frame.sampleBuffer, orientation: .up),
            observation.confidence >= ScanTuning.minimumConfidence
        else {
            reset()
            return nil
        }

        let quad = Quad(
            topLeft: observation.topLeft.toImageCoordinates(frameSize, origin: .upperLeft),
            topRight: observation.topRight.toImageCoordinates(frameSize, origin: .upperLeft),
            bottomRight: observation.bottomRight.toImageCoordinates(frameSize, origin: .upperLeft),
            bottomLeft: observation.bottomLeft.toImageCoordinates(frameSize, origin: .upperLeft)
        )

        // Glare is the only signal that costs anything, so it is sampled rather
        // than measured on every frame.
        if frameIndex % 4 == 0 {
            lastGlare = hasGlare(in: pixelBuffer, quad: quad, frameSize: frameSize)
        }

        let display = smooth(quad)
        let coaching = evaluate(quad: quad, frameSize: frameSize)

        var shouldCapture = false
        if case .locking(let progress) = coaching, progress >= 1 {
            shouldCapture = true
            steadySince = nil
        }

        return Detection(
            quad: display,
            frameSize: frameSize,
            coaching: coaching,
            shouldCapture: shouldCapture
        )
    }

    /// The most recent unsmoothed quad, which is what a capture should be
    /// corrected against. Written on the capture queue and read from the main
    /// actor when the shutter fires, so it is the one thing here that needs a lock.
    private let quadLock = NSLock()
    private var _latestRawQuad: Quad?

    var latestRawQuad: Quad? {
        quadLock.lock()
        defer { quadLock.unlock() }
        return _latestRawQuad
    }

    private func evaluate(quad: Quad, frameSize: CGSize) -> CoachingState {
        quadLock.lock()
        _latestRawQuad = quad
        quadLock.unlock()

        recent.append(quad)
        if recent.count > ScanTuning.driftWindow { recent.removeFirst() }

        if quad.areaFraction(in: frameSize) < ScanTuning.minimumAreaFraction {
            steadySince = nil
            return .closer
        }
        if quad.skew > ScanTuning.maximumSkew {
            steadySince = nil
            return .straighten
        }
        if lastGlare {
            steadySince = nil
            return .glare
        }

        let drift = averageDrift(in: frameSize)
        guard recent.count >= ScanTuning.driftWindow, drift < ScanTuning.maximumDrift else {
            steadySince = nil
            return .holdStill
        }

        let start = steadySince ?? Date()
        if steadySince == nil { steadySince = start }
        let elapsed = Date().timeIntervalSince(start)
        return .locking(progress: min(1, elapsed / ScanTuning.lockDuration))
    }

    private func averageDrift(in frameSize: CGSize) -> CGFloat {
        guard recent.count > 1 else { return .greatestFiniteMagnitude }
        var total: CGFloat = 0
        for index in 1..<recent.count {
            total += recent[index].drift(from: recent[index - 1], in: frameSize)
        }
        return total / CGFloat(recent.count - 1)
    }

    /// Exponential smoothing so the drawn outline follows the card without the
    /// per-frame jitter the detector has.
    private func smooth(_ quad: Quad) -> Quad {
        guard let previous = smoothed else {
            smoothed = quad
            return quad
        }
        let t = ScanTuning.smoothing
        func blend(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }
        let next = Quad(
            topLeft: blend(previous.topLeft, quad.topLeft),
            topRight: blend(previous.topRight, quad.topRight),
            bottomRight: blend(previous.bottomRight, quad.bottomRight),
            bottomLeft: blend(previous.bottomLeft, quad.bottomLeft)
        )
        smoothed = next
        return next
    }

    // MARK: - Glare

    private func hasGlare(in pixelBuffer: CVPixelBuffer, quad: Quad, frameSize: CGSize) -> Bool {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        // Core Image works bottom-up, so the quad's bounding box is flipped back.
        let xs = quad.corners.map(\.x)
        let ys = quad.corners.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else { return false }
        let rect = CGRect(
            x: minX,
            y: frameSize.height - maxY,
            width: maxX - minX,
            height: maxY - minY
        ).intersection(image.extent)
        guard !rect.isNull, rect.width > 8, rect.height > 8 else { return false }

        let histogram = CIFilter.areaHistogram()
        histogram.inputImage = image.cropped(to: rect)
        histogram.extent = rect
        histogram.count = 32
        histogram.scale = 1
        guard let output = histogram.outputImage else { return false }

        var bins = [Float](repeating: 0, count: 32 * 4)
        ImagePipeline.context.render(
            output,
            toBitmap: &bins,
            rowBytes: 32 * 4 * MemoryLayout<Float>.size,
            bounds: CGRect(x: 0, y: 0, width: 32, height: 1),
            format: .RGBAf,
            colorSpace: nil
        )

        // Counts are normalised by the filter, so the top bins are already the
        // fraction of pixels at that brightness.
        let firstClippedBin = Int(ScanTuning.glareLevel * 32)
        var clipped: Float = 0
        for bin in firstClippedBin..<32 {
            clipped += bins[bin * 4 + 1]  // green channel stands in for luminance
        }
        return CGFloat(clipped) > ScanTuning.glareFraction
    }
}
