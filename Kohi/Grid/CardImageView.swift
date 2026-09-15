import SwiftUI

/// Draws a card's scan or poster at whatever size it is asked for, pulling the
/// smallest thumbnail bucket that still covers that size.
struct CardImageView: View {
    let card: CoffeeCard
    /// Width the image will be drawn at, in points. Picks the bucket.
    let targetWidth: CGFloat
    var variant: ThumbnailVariant = .scan

    @Environment(\.displayScale) private var displayScale
    @State private var image: CGImage?
    @State private var loadedKey: TaskKey?

    /// The effective variant, falling back to scan when the poster is not ready.
    private var effectiveVariant: ThumbnailVariant {
        if variant == .poster, card.poster == .ready { return .poster }
        return .scan
    }

    /// Whether the poster is requested and currently generating.
    private var isPosterPending: Bool {
        variant == .poster && card.poster == .pending
    }

    private var bucket: Int {
        ThumbnailCache.bucket(forWidth: targetWidth, scale: displayScale)
    }

    private var aspectRatio: Double {
        if let image, effectiveVariant == .poster {
            return Double(image.width) / Double(image.height)
        }
        if variant == .poster, card.poster == .ready || card.poster == .pending {
            return PosterLayout.aspectRatio
        }
        return card.aspectRatio
    }

    var body: some View {
        ZStack {
            if isPosterPending {
                Rectangle()
                    .fill(Palette.paperShade)
                    .overlay { ShimmerBar() }
            } else if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
            } else {
                Rectangle()
                    .fill(Palette.paperShade)
            }
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .animation(Motion.quick, value: image == nil)
        .animation(Motion.quick, value: card.poster)
        .task(id: TaskKey(id: card.id, bucket: bucket, variant: effectiveVariant, poster: card.poster)) {
            let currentKey = TaskKey(
                id: card.id,
                bucket: bucket,
                variant: effectiveVariant,
                poster: card.poster
            )
            if isPosterPending {
                image = nil
                loadedKey = nil
                return
            }
            if let loadedKey, loadedKey == currentKey { return }
            if let loadedKey, loadedKey.variant == currentKey.variant,
               loadedKey.bucket >= currentKey.bucket,
               loadedKey.poster == currentKey.poster { return }
            if let hit = ThumbnailCache.shared.cached(card.id, bucket: bucket, variant: effectiveVariant) {
                image = hit
                self.loadedKey = currentKey
                return
            }
            let loaded = await ThumbnailCache.shared.image(for: card, bucket: bucket, variant: effectiveVariant)
            guard !Task.isCancelled else { return }
            image = loaded
            self.loadedKey = loaded == nil ? nil : currentKey
        }
    }

    private struct TaskKey: Equatable {
        let id: UUID
        let bucket: Int
        let variant: ThumbnailVariant
        let poster: PosterState
    }
}
