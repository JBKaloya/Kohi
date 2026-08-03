import CoreGraphics
import os
import SwiftUI

/// What happens between the shutter and the archive.
///
/// Auto-detection is right most of the time and wrong exactly when the table is
/// busy, so this is where you get to disagree with it. The corners start where
/// the detector put them; drag any of them and the crop follows.
struct ScanReviewScreen: View {
    let capture: CapturedCard
    let onUse: (ScanResult) -> Void
    let onRetake: () -> Void

    @State private var quad: Quad
    @State private var enhance = true
    /// Downsampled for the screen. Nothing here touches the full still.
    @State private var plain: CGImage?
    @State private var enhanced: CGImage?

    /// Longest edge of the working copy. Big enough to place a corner on, small
    /// enough that the enhancer runs while you are still looking at it.
    private static let previewPixels = 1400

    init(capture: CapturedCard, onUse: @escaping (ScanResult) -> Void, onRetake: @escaping () -> Void) {
        self.capture = capture
        self.onUse = onUse
        self.onRetake = onRetake
        _quad = State(initialValue: capture.quad ?? .inset(in: capture.pixelSize))
    }

    private var shown: CGImage? {
        enhance ? (enhanced ?? plain) : plain
    }

    var body: some View {
        ZStack {
            Palette.scanBackdrop.ignoresSafeArea()

            if let shown {
                ZStack {
                    Image(decorative: shown, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)

                    QuadEditor(quad: $quad, imageSize: capture.pixelSize, preview: shown)
                }
                .padding(.horizontal, 20)
                .padding(.top, 54)
                .padding(.bottom, 104)
            } else {
                ProgressView().tint(.white)
            }

            controls
        }
        .animation(Motion.quick, value: enhance)
        .task { await makePreviews() }
    }

    private var controls: some View {
        VStack {
            HStack {
                Button("Retake", action: onRetake)
                    .font(Typography.subtitle)
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                enhanceToggle
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            Spacer()

            Button {
                onUse(ScanResult(image: capture.image, quad: quad, enhance: enhance))
            } label: {
                Text("Use")
                    .font(Typography.coaching)
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(.white, in: .capsule)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 46)
            .padding(.bottom, 18)
        }
    }

    private var enhanceToggle: some View {
        Button {
            enhance.toggle()
        } label: {
            // "Washed" is the processing method that gives a clean, bright cup,
            // and it is exactly what the filter does to the scan.
            HStack(spacing: 7) {
                Image(systemName: enhance ? "drop.fill" : "drop")
                    .font(.system(size: 13, weight: .medium))
                Text("Washed")
                    .font(Typography.tag)
            }
            .foregroundStyle(enhance ? Palette.ink : .white.opacity(0.85))
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(enhance ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.16)), in: .capsule)
        }
        .buttonStyle(.plain)
    }

    /// Both versions are rendered once, off the main actor, so the toggle is a
    /// swap rather than a filter run.
    private func makePreviews() async {
        let source = capture.image
        let pixels = Self.previewPixels

        let base = await Task.detached(priority: .userInitiated) {
            ImagePipeline.downsample(source, maxPixel: pixels)
        }.value
        plain = base

        guard let base else { return }
        enhanced = await Task.detached(priority: .userInitiated) {
            ImagePipeline.enhance(base)
        }.value
        if enhanced == nil {
            Log.app.notice("scan look: enhancer produced nothing, showing the plain scan")
        }
    }
}
