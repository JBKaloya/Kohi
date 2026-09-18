import SwiftUI

/// The card as a thing rather than a picture: it sits above the paper and catches
/// the light as you tilt the phone. Pinch zooms *inside* the silhouette — the
/// object never leaves its seat, and tilt / sheen stop while you inspect.
struct CardObject: View {
    let card: CoffeeCard
    let width: CGFloat
    var variant: ThumbnailVariant = .poster

    @Environment(\.scenePhase) private var scenePhase
    @State private var tilt = DeviceTilt()
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var inspect: CGImage?

    private var zoomed: Bool { scale > 1 }

    var body: some View {
        lens
            .frame(width: width)
            .rotation3DEffect(
                .degrees(zoomed ? 0 : tilt.roll * Motion.Parallax.tilt),
                axis: (x: 0, y: 1, z: 0),
                perspective: Motion.Parallax.perspective
            )
            .rotation3DEffect(
                .degrees(zoomed ? 0 : -tilt.pitch * Motion.Parallax.tilt),
                axis: (x: 1, y: 0, z: 0),
                perspective: Motion.Parallax.perspective
            )
            .offset(
                x: zoomed ? 0 : tilt.roll * Motion.Parallax.shift,
                y: zoomed ? 0 : tilt.pitch * Motion.Parallax.shift
            )
            .shadow(
                color: .black.opacity(0.10),
                radius: width * 0.006,
                x: 0, y: width * 0.003
            )
            .shadow(
                color: Palette.cardShadow,
                radius: width * Motion.Object.shadowRadius,
                x: zoomed ? 0 : -tilt.roll * Motion.Parallax.shadowCounterShift,
                y: width * Motion.Object.shadowDrop - (zoomed ? 0 : tilt.pitch * Motion.Parallax.shadowCounterShift)
            )
            .contentShape(Rectangle())
            .gesture(pinch)
            .highPriorityGesture(pan, including: zoomed ? .all : .none)
            .onTapGesture(count: 2, perform: toggle)
            .accessibilityHint("Pinch or double tap to zoom inside the card")
            .task { tilt.start() }
            .onDisappear { tilt.stop() }
            .onChange(of: scenePhase) { _, phase in
                guard !zoomed else { return }
                phase == .active ? tilt.start() : tilt.stop()
            }
            .onChange(of: variant) { _, _ in resetLens() }
            .onChange(of: card.id) { _, _ in resetLens() }
    }

    private var plate: some View {
        CardImageView(card: card, targetWidth: width, variant: variant)
    }

    /// Layout stays the resting plate. Zoom is a transform inside the mask.
    private var lens: some View {
        plate
            .opacity(0)
            .overlay {
                ZStack {
                    drawable
                        .scaleEffect(scale)
                        .offset(offset)
                    if !zoomed, tilt.isAvailable {
                        sheen
                    }
                }
            }
            .mask(plate)
    }

    @ViewBuilder
    private var drawable: some View {
        if let inspect, zoomed {
            Image(decorative: inspect, scale: 1)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        } else {
            plate
        }
    }

    /// A soft band of light that slides across the card as you tilt it.
    private var sheen: some View {
        let centre = 0.5 + tilt.roll * Motion.Parallax.sheenTravel / 2
        let half = Motion.Parallax.sheenWidth / 2
        return LinearGradient(
            stops: [
                .init(color: .clear, location: min(max(centre - half, 0), 1)),
                .init(
                    color: .white.opacity(Motion.Parallax.sheenOpacity),
                    location: min(max(centre, 0), 1)
                ),
                .init(color: .clear, location: min(max(centre + half, 0), 1)),
            ],
            startPoint: UnitPoint(x: 0, y: 0.15),
            endPoint: UnitPoint(x: 1, y: 0.85)
        )
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
        .mask(plate)
    }

    private var pinch: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                armInspect()
                scale = clamped(lastScale * value.magnification)
                offset = clampedOffset(lastOffset)
                freezeMotionIfNeeded()
            }
            .onEnded { _ in
                settle()
            }
    }

    private var pan: some Gesture {
        DragGesture()
            .onChanged { value in
                guard zoomed else { return }
                offset = clampedOffset(CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                ))
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }

    private func toggle() {
        armInspect()
        withAnimation(Motion.snappy) {
            if zoomed {
                scale = 1
                lastScale = 1
                offset = .zero
                lastOffset = .zero
            } else {
                scale = Motion.Object.zoomTap
                lastScale = Motion.Object.zoomTap
            }
        }
        freezeMotionIfNeeded()
    }

    private func settle() {
        let next = clamped(scale)
        withAnimation(Motion.snappy) {
            scale = next
            lastScale = next
            if next <= 1 {
                offset = .zero
                lastOffset = .zero
            } else {
                offset = clampedOffset(offset)
                lastOffset = offset
            }
        }
        freezeMotionIfNeeded()
    }

    private func resetLens() {
        scale = 1
        lastScale = 1
        offset = .zero
        lastOffset = .zero
        inspect = nil
        if scenePhase == .active { tilt.start() }
    }

    private func freezeMotionIfNeeded() {
        if zoomed {
            tilt.stop()
        } else if scenePhase == .active {
            tilt.start()
        }
    }

    private func armInspect() {
        guard inspect == nil else { return }
        let id = card.id
        let hasMask = card.hasMask
        let variant = variant
        Task {
            inspect = await Task.detached(priority: .userInitiated) {
                switch variant {
                case .poster where ImageStore.shared.exists(id, kind: .poster):
                    ImageCodec.downsample(
                        ImageStore.shared.url(for: id, kind: .poster),
                        maxPixel: 4096
                    )
                case .poster, .scan:
                    ImagePipeline.composed(id: id, hasMask: hasMask, maxPixel: 4096)
                }
            }.value
        }
    }

    private func clamped(_ value: CGFloat) -> CGFloat {
        min(max(value, Motion.Object.zoomRange.lowerBound), Motion.Object.zoomRange.upperBound)
    }

    /// Keep the magnified image covering the silhouette — no empty paper inside the mask.
    private func clampedOffset(_ proposed: CGSize) -> CGSize {
        let height = plateHeight
        let maxX = max(0, width * (scale - 1) / 2)
        let maxY = max(0, height * (scale - 1) / 2)
        return CGSize(
            width: min(max(proposed.width, -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY)
        )
    }

    private var plateHeight: CGFloat {
        let ratio: Double
        if variant == .poster, card.poster == .ready || card.poster == .pending {
            ratio = PosterLayout.aspectRatio
        } else {
            ratio = card.aspectRatio
        }
        guard ratio > 0 else { return width }
        return width / CGFloat(ratio)
    }
}
