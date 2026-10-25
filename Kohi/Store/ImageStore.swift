import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The files that make up one card on disk.
nonisolated enum CardImageKind: Hashable, Sendable {
    /// The raw capture, kept so the pipeline can be re-run without rescanning.
    case original
    /// Perspective-corrected and cropped. This is the archival image.
    case flat
    /// 8-bit grayscale cut-out mask, written only when the mask looked plausible.
    case mask
    /// Downsampled render for the grid, at one of `ThumbnailCache.buckets`.
    case thumbnail(Int)
    /// Flat image for an attachment linked to this card.
    case attachment(UUID)
    /// Downsampled thumbnail of an attachment.
    case attachmentThumbnail(UUID, Int)

    var filename: String {
        switch self {
        case .original: "original.heic"
        case .flat: "flat.heic"
        case .mask: "mask.png"
        case .thumbnail(let size): "thumb-\(size)-v2.heic"
        case .attachment(let id): "attach-\(id.uuidString).heic"
        case .attachmentThumbnail(let id, let size): "attach-\(id.uuidString)-\(size).heic"
        }
    }
}

/// Owns the on-disk layout. Nothing else in the app builds a path by hand.
///
///     Application Support/
///       cards.json
///       Cards/<uuid>/{original,flat}.heic, mask.png, thumb-<n>.heic
nonisolated struct ImageStore: Sendable {
    static let shared = ImageStore()

    let root: URL
    let indexURL: URL

    init() {
        let support = URL.applicationSupportDirectory
        root = support.appending(path: "Cards", directoryHint: .isDirectory)
        indexURL = support.appending(path: "cards.json", directoryHint: .notDirectory)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func directory(for id: UUID) -> URL {
        root.appending(path: id.uuidString, directoryHint: .isDirectory)
    }

    func url(for id: UUID, kind: CardImageKind) -> URL {
        directory(for: id).appending(path: kind.filename, directoryHint: .notDirectory)
    }

    func exists(_ id: UUID, kind: CardImageKind) -> Bool {
        FileManager.default.fileExists(atPath: url(for: id, kind: kind).path(percentEncoded: false))
    }

    func write(_ data: Data, for id: UUID, kind: CardImageKind) throws {
        let directory = directory(for: id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url(for: id, kind: kind), options: .atomic)
    }

    /// Removes every file belonging to a card. Called when a card is deleted.
    func removeAll(for id: UUID) {
        try? FileManager.default.removeItem(at: directory(for: id))
    }

    /// Removes stale thumbnail files left behind by a processing version bump.
    func purgeOrphanedThumbnails() {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil
        ) else { return }
        let stalePattern = /^thumb-\d+\.heic$/
        for dir in dirs where dir.hasDirectoryPath {
            guard let files = try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil
            ) else { continue }
            for file in files where file.lastPathComponent.wholeMatch(of: stalePattern) != nil {
                try? fm.removeItem(at: file)
            }
        }
    }

    /// Total bytes on disk, for the debug readout only.
    func byteCount() -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }
}

/// Encode and decode helpers. HEIC for anything photographic, PNG for masks
/// because they need to stay lossless.
nonisolated enum ImageCodec {
    static func encodeHEIC(_ image: CGImage, quality: CGFloat = 0.9) -> Data? {
        encode(image, type: UTType.heic, quality: quality)
    }

    static func encodePNG(_ image: CGImage) -> Data? {
        encode(image, type: UTType.png, quality: 1)
    }

    /// JPEG for anything leaving the device: HEIC saves disk, but the vision
    /// API wants the format everything understands.
    static func encodeJPEG(_ image: CGImage, quality: CGFloat = 0.8) -> Data? {
        encode(image, type: UTType.jpeg, quality: quality)
    }

    private static func encode(_ image: CGImage, type: UTType, quality: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, type.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(
            destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    static func decode(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    static func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Decodes straight to the size we need. This is the call that keeps full
    /// resolution scans off the scrolling path.
    static func downsample(_ url: URL, maxPixel: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Decodes encoded photo data with its EXIF orientation already applied, so
    /// callers never have to carry an orientation alongside the image.
    static func decodeOriented(_ data: Data, maxPixel: Int = 6000) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Pixel dimensions without decoding the image.
    static func pixelSize(of url: URL) -> CGSize? {
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return CGSize(width: width, height: height)
    }
}
