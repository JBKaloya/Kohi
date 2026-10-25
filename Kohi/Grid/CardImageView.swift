import SwiftUI

/// Draws a card's scan at whatever size it is asked for, pulling the
/// smallest thumbnail bucket that still covers that size.
struct CardImageView: View {
    let card: CoffeeCard
    /// Width the image will be drawn at, in points. Picks the bucket.
    let targetWidth: CGFloat
    /// When set, the view is that ratio regardless of the scan. The home
    /// grid locks 4:5 so tiles do not jump as cards land.
    var aspect: Double? = nil

    @Environment(\.displayScale) private var displayScale
    @State private var image: CGImage?
    @State private var loadedKey: TaskKey?

    private var bucket: Int {
        ThumbnailCache.bucket(forWidth: targetWidth, scale: displayScale)
    }

    private var aspectRatio: Double {
        if let aspect { return aspect }
        if let image {
            return Double(image.width) / Double(image.height)
        }
        return card.aspectRatio
    }

    var body: some View {
        ZStack {
            if let image {
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
        .task(id: TaskKey(id: card.id, bucket: bucket)) {
            let currentKey = TaskKey(id: card.id, bucket: bucket)
            if let loadedKey, loadedKey == currentKey { return }
            if let loadedKey, loadedKey.bucket >= currentKey.bucket { return }
            if let hit = ThumbnailCache.shared.cached(card.id, bucket: bucket) {
                image = hit
                self.loadedKey = currentKey
                return
            }
            let loaded = await ThumbnailCache.shared.image(for: card, bucket: bucket)
            guard !Task.isCancelled else { return }
            image = loaded
            self.loadedKey = loaded == nil ? nil : currentKey
        }
    }

    private struct TaskKey: Equatable {
        let id: UUID
        let bucket: Int
    }
}
