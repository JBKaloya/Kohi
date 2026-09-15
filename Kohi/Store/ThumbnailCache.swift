import CoreGraphics
import Foundation

/// Which image variant to load — the scan (flat + mask composite) or the
/// AI-generated poster.
nonisolated enum ThumbnailVariant: Hashable, Sendable {
    case scan
    case poster
}

/// Memory cache in front of the thumbnail files on disk. Nothing on the scroll
/// path is ever allowed to decode a full resolution scan, and this is what
/// enforces that.
nonisolated final class ThumbnailCache: @unchecked Sendable {
    static let shared = ThumbnailCache()

    /// Longest-edge sizes we keep on disk. 512 covers three and four column
    /// layouts at 3x; 1024 covers one and two columns and the detail view's
    /// first paint.
    static let buckets = [512, 1024]

    /// NSCache is documented as thread-safe, which is why this type can be
    /// `@unchecked Sendable` and used from any context.
    private let cache = NSCache<NSString, CacheEntry>()
    private let renderer = ThumbnailRenderer()

    private init() {
        cache.totalCostLimit = 96 * 1024 * 1024
    }

    /// The smallest bucket that still covers `pointWidth` at the screen's scale.
    static func bucket(forWidth pointWidth: CGFloat, scale: CGFloat) -> Int {
        let needed = pointWidth * scale
        return buckets.first { CGFloat($0) >= needed } ?? buckets[buckets.count - 1]
    }

    func cached(_ id: UUID, bucket: Int, variant: ThumbnailVariant = .scan) -> CGImage? {
        cache.object(forKey: key(id, bucket, variant))?.image
    }

    /// Loads from memory, then disk, then renders. Rendering and decoding always
    /// happen off the calling actor.
    func image(for card: CoffeeCard, bucket: Int, variant: ThumbnailVariant = .scan) async -> CGImage? {
        if let hit = cached(card.id, bucket: bucket, variant: variant) { return hit }

        let image: CGImage?
        switch variant {
        case .scan:
            image = await renderer.image(id: card.id, hasMask: card.hasMask, bucket: bucket)
        case .poster:
            image = await renderer.posterImage(id: card.id, bucket: bucket)
        }
        if let image { store(image, id: card.id, bucket: bucket, variant: variant) }
        return image
    }

    /// Renders thumbnails without returning them, so a freshly scanned card, or
    /// the bucket a pinch is about to need, is ready before the grid asks.
    func warm(_ card: CoffeeCard, buckets: [Int] = ThumbnailCache.buckets) {
        for bucket in buckets {
            if cached(card.id, bucket: bucket, variant: .scan) == nil {
                Task(priority: .utility) { _ = await image(for: card, bucket: bucket, variant: .scan) }
            }
            if card.poster == .ready, cached(card.id, bucket: bucket, variant: .poster) == nil {
                Task(priority: .utility) { _ = await image(for: card, bucket: bucket, variant: .poster) }
            }
        }
    }

    func invalidate(_ id: UUID) {
        for bucket in Self.buckets {
            cache.removeObject(forKey: key(id, bucket, .scan))
            cache.removeObject(forKey: key(id, bucket, .poster))
        }
    }

    fileprivate static func load(id: UUID, hasMask: Bool, bucket: Int) -> CGImage? {
        let store = ImageStore.shared
        let thumbURL = store.url(for: id, kind: .thumbnail(bucket))
        if store.exists(id, kind: .thumbnail(bucket)),
           let image = ImageCodec.decode(thumbURL) {
            return image
        }
        return ImagePipeline.makeThumbnail(id: id, hasMask: hasMask, bucket: bucket)
    }

    fileprivate static func loadPoster(id: UUID, bucket: Int) -> CGImage? {
        let store = ImageStore.shared
        let thumbURL = store.url(for: id, kind: .posterThumbnail(bucket))
        if store.exists(id, kind: .posterThumbnail(bucket)),
           let image = ImageCodec.decode(thumbURL) {
            return image
        }
        return ImagePipeline.makePosterThumbnail(id: id, bucket: bucket)
    }

    private func store(_ image: CGImage, id: UUID, bucket: Int, variant: ThumbnailVariant) {
        cache.setObject(
            CacheEntry(image: image),
            forKey: key(id, bucket, variant),
            cost: image.bytesPerRow * image.height
        )
    }

    private func key(_ id: UUID, _ bucket: Int, _ variant: ThumbnailVariant) -> NSString {
        switch variant {
        case .scan: "\(id.uuidString)-\(bucket)" as NSString
        case .poster: "\(id.uuidString)-poster-\(bucket)" as NSString
        }
    }

    private final class CacheEntry {
        let image: CGImage
        init(image: CGImage) { self.image = image }
    }
}

/// Serialises thumbnail rendering and coalesces duplicate requests.
///
/// Both matter. HEIC decoding runs on a shared hardware decoder, so asking for a
/// screenful of cards at once does not go faster — it queues inside the decoder,
/// where the work is invisible and cannot be cancelled or reordered. Keeping one
/// render in flight here keeps that queue in the app, where a memory hit can
/// still overtake it. Coalescing means the two views that want the same image
/// during a pinch decode it once.
private actor ThumbnailRenderer {
    private var inFlight: [Key: Task<CGImage?, Never>] = [:]
    private let queue = DispatchQueue(label: "studio.jbk.kohiapp.thumbnails", qos: .userInitiated)

    func image(id: UUID, hasMask: Bool, bucket: Int) async -> CGImage? {
        let key = Key(id: id, bucket: bucket, variant: .scan)
        if let existing = inFlight[key] { return await existing.value }

        let task = Task { await self.render(id: id, hasMask: hasMask, bucket: bucket) }
        inFlight[key] = task
        let image = await task.value
        if inFlight[key] == task { inFlight[key] = nil }
        return image
    }

    func posterImage(id: UUID, bucket: Int) async -> CGImage? {
        let key = Key(id: id, bucket: bucket, variant: .poster)
        if let existing = inFlight[key] { return await existing.value }

        let task = Task { await self.renderPoster(id: id, bucket: bucket) }
        inFlight[key] = task
        let image = await task.value
        if inFlight[key] == task { inFlight[key] = nil }
        return image
    }

    private func render(id: UUID, hasMask: Bool, bucket: Int) async -> CGImage? {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: ThumbnailCache.load(id: id, hasMask: hasMask, bucket: bucket))
            }
        }
    }

    private func renderPoster(id: UUID, bucket: Int) async -> CGImage? {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: ThumbnailCache.loadPoster(id: id, bucket: bucket))
            }
        }
    }

    private struct Key: Hashable {
        let id: UUID
        let bucket: Int
        let variant: ThumbnailVariant
    }
}
