import SwiftUI

/// Draws a card's scan at whatever size it is asked for, pulling the smallest
/// thumbnail bucket that still covers that size.
struct CardImageView: View {
    let card: CoffeeCard
    /// Width the image will be drawn at, in points. Picks the bucket.
    let targetWidth: CGFloat

    @Environment(\.displayScale) private var displayScale
    @State private var image: CGImage?
    @State private var loadedBucket: Int?

    private var bucket: Int {
        ThumbnailCache.bucket(forWidth: targetWidth, scale: displayScale)
    }

    var body: some View {
        ZStack {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
            } else {
                // Holds the tile's shape while the decode happens, so the grid
                // never reflows when an image arrives.
                Rectangle()
                    .fill(Palette.paperShade)
            }
        }
        .aspectRatio(card.aspectRatio, contentMode: .fit)
        .animation(Motion.quick, value: image == nil)
        .task(id: TaskKey(id: card.id, bucket: bucket)) {
            // A larger bucket already in hand is better than a placeholder while
            // the smaller one loads.
            if let loadedBucket, loadedBucket >= bucket { return }
            if let hit = ThumbnailCache.shared.cached(card.id, bucket: bucket) {
                image = hit
                loadedBucket = bucket
                return
            }
            let loaded = await ThumbnailCache.shared.image(for: card, bucket: bucket)
            guard !Task.isCancelled else { return }
            image = loaded
            loadedBucket = loaded == nil ? nil : bucket
        }
    }

    private struct TaskKey: Equatable {
        let id: UUID
        let bucket: Int
    }
}
