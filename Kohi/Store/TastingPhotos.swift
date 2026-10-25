import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Photos of a tasting, on disk and in the `cards` bucket.
///
///     Application Support/Tastings/<tasting id>/<photo>.jpg
///     cards/<user>/tastings/<tasting id>/<photo>.jpg
///
/// Never in a card's folder: a tasting's photos are its own, whether or not
/// it links a card, and survive that card being deleted.
nonisolated enum TastingPhotos {
    static var root: URL {
        URL.applicationSupportDirectory.appending(path: "Tastings", directoryHint: .isDirectory)
    }

    static func directory(for tastingID: UUID) -> URL {
        root.appending(path: tastingID.uuidString, directoryHint: .isDirectory)
    }

    static func url(tastingID: UUID, name: String) -> URL {
        directory(for: tastingID).appending(path: name, directoryHint: .notDirectory)
    }

    static func exists(tastingID: UUID, name: String) -> Bool {
        FileManager.default.fileExists(atPath: url(tastingID: tastingID, name: name).path(percentEncoded: false))
    }

    static func remotePath(userID: UUID, tastingID: UUID, name: String) -> String {
        "\(userID.uuidString.lowercased())/tastings/\(tastingID.uuidString.lowercased())/\(name)"
    }

    /// Re-encodes to a JPEG no larger than 2048 px on the long side, and
    /// returns the file name to store on the tasting.
    @discardableResult
    static func save(_ data: Data, tastingID: UUID) -> String? {
        guard let jpeg = downsampled(data, maxPixel: 2048) else { return nil }
        let name = "photo-\(UUID().uuidString.lowercased()).jpg"
        return write(jpeg, tastingID: tastingID, name: name) ? name : nil
    }

    @discardableResult
    static func write(_ data: Data, tastingID: UUID, name: String) -> Bool {
        do {
            try FileManager.default.createDirectory(at: directory(for: tastingID), withIntermediateDirectories: true)
            try data.write(to: url(tastingID: tastingID, name: name), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    static func image(tastingID: UUID, name: String, maxPixel: Int = 400) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url(tastingID: tastingID, name: name) as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ] as CFDictionary)
    }

    private static func downsampled(_ data: Data, maxPixel: Int) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: maxPixel,
              ] as CFDictionary) else { return nil }
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return out as Data
    }
}

struct TastingPhotoThumb: View {
    let tastingID: UUID
    let name: String
    var size: CGFloat = 64

    @State private var image: CGImage?

    var body: some View {
        ZStack {
            Palette.hairline.opacity(0.4)
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .task(id: name) {
            image = TastingPhotos.image(tastingID: tastingID, name: name, maxPixel: Int(size * 3))
        }
    }
}
