import CoreGraphics
import Foundation

/// Files that sit beside a scan and are not part of the archive upload.
/// `Cards/<uuid>/kohi-tile-<hash>.png`, `stamp.png`, `stamp.json`, `ocr.json`.
nonisolated enum CardFiles {
    static func directory(_ id: UUID) -> URL {
        ImageStore.shared.directory(for: id)
    }

    static func kohiTile(id: UUID, token: String) -> URL {
        directory(id).appending(path: "kohi-tile-\(token).png")
    }

    static func stampPNG(_ id: UUID) -> URL {
        directory(id).appending(path: "stamp.png")
    }

    static func stampJSON(_ id: UUID) -> URL {
        directory(id).appending(path: "stamp.json")
    }

    static func stampShapeJSON(_ id: UUID) -> URL {
        directory(id).appending(path: "stamp-shape.json")
    }

    static func readStampShape(_ id: UUID) -> MarkShape? {
        guard let data = try? Data(contentsOf: stampShapeJSON(id)),
              let shape = try? JSONDecoder().decode(MarkShape.self, from: data),
              shape.version == MarkShape.version
        else { return nil }
        return shape
    }

    static func writeStampShape(_ shape: MarkShape, id: UUID) {
        let url = stampShapeJSON(id)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(shape) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func removeStampShape(_ id: UUID) {
        try? FileManager.default.removeItem(at: stampShapeJSON(id))
    }

    static func ocrJSON(_ id: UUID) -> URL {
        directory(id).appending(path: "ocr.json")
    }

    static func scanRevision(_ id: UUID) -> String {
        let url = ImageStore.shared.url(for: id, kind: .flat)
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let size = values?.fileSize ?? 0
        let date = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        return "\(size)-\(date)"
    }

    static func readKohi(id: UUID, token: String) -> CGImage? {
        let url = kohiTile(id: id, token: token)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
        return ImageCodec.decode(url)
    }

    static func writeKohi(_ image: CGImage, id: UUID, token: String) {
        guard let data = ImageCodec.encodePNG(image) else { return }
        let url = kohiTile(id: id, token: token)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    static func readStamp(_ id: UUID) -> CGImage? {
        ImageCodec.decode(stampPNG(id))
    }

    static func writeStamp(_ image: CGImage, id: UUID) {
        guard let data = ImageCodec.encodePNG(image) else { return }
        let url = stampPNG(id)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    static func removeStamp(_ id: UUID) {
        try? FileManager.default.removeItem(at: stampPNG(id))
    }

    static func loadStampFile(_ id: UUID) -> StampFile? {
        guard let data = try? Data(contentsOf: stampJSON(id)) else { return nil }
        return try? JSONDecoder().decode(StampFile.self, from: data)
    }

    static func writeStampFile(_ file: StampFile, id: UUID) {
        let url = stampJSON(id)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(file) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Drops rendered Kohi tiles for one coffee. The stamp and the scan stay.
    static func invalidateKohi(id: UUID) {
        let folder = directory(id)
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else {
            return
        }
        for file in files where file.lastPathComponent.hasPrefix("kohi-") {
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// Drops every tile but the one for `token`. Called after the new tile is written.
    static func removeStaleKohi(id: UUID, keeping token: String) {
        let keep = kohiTile(id: id, token: token).lastPathComponent
        for name in kohiTileNames(id) where name != keep {
            try? FileManager.default.removeItem(at: directory(id).appending(path: name))
        }
    }

    static func kohiTileNames(_ id: UUID) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory(id).path(percentEncoded: false))) ?? []
        return names.filter { $0.hasPrefix("kohi-tile-") }
    }

    static func hasKohi(id: UUID, token: String) -> Bool {
        FileManager.default.fileExists(atPath: kohiTile(id: id, token: token).path(percentEncoded: false))
    }
}
