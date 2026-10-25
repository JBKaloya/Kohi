import CoreGraphics
import Foundation
import Observation

/// Stamp decisions for the open archive. The files on disk stay the record;
/// this only publishes them so a tile or a fiche can update without a reload.
@MainActor
@Observable
final class StampLibrary {
    @ObservationIgnored private var files: [UUID: StampFile] = [:]
    @ObservationIgnored private var images: [UUID: CGImage] = [:]
    @ObservationIgnored private var shapes: [UUID: MarkShape] = [:]
    @ObservationIgnored private var loaded: Set<UUID> = []
    private(set) var revisions: [UUID: Int] = [:]

    func revision(for id: UUID) -> Int { revisions[id, default: 0] }

    func file(for id: UUID) -> StampFile? {
        if loaded.contains(id) { return files[id] }
        let stored = CardFiles.loadStampFile(id)
        files[id] = stored
        loaded.insert(id)
        return stored
    }

    func style(for id: UUID) -> SymbolStyle {
        file(for: id)?.style ?? .auto
    }

    /// Auto ran and the pack was text, a slab, or noise.
    func rejected(_ id: UUID) -> Bool {
        guard let file = file(for: id) else { return false }
        return file.stamp == nil && file.pipelineVersion == InkStamp.pipelineVersion
    }

    /// The symbol as the ground draws it: the vector shape, else the soft bitmap.
    func mark(for id: UUID) -> MarkSource? {
        guard let file = file(for: id), file.stamp != nil, file.stamp?.source != .library else { return nil }
        if file.vectorVersion == MarkShape.version {
            if let cached = shapes[id] { return .shape(cached) }
            if let shape = CardFiles.readStampShape(id) {
                shapes[id] = shape
                return .shape(shape)
            }
        }
        if let cached = images[id] { return .bitmap(cached) }
        guard let image = CardFiles.readStamp(id) else { return nil }
        images[id] = image
        return .bitmap(image)
    }

    func setStyle(_ style: SymbolStyle, for id: UUID) {
        var file = file(for: id) ?? StampFile(
            style: style,
            stamp: nil,
            scanRevision: CardFiles.scanRevision(id),
            pipelineVersion: 0,
            manualRect: nil
        )
        file.style = style
        replace(file, for: id)
    }

    /// The tile for the old token stays until the new one is written; the composer clears it.
    func replace(_ file: StampFile, for id: UUID) {
        files[id] = file
        loaded.insert(id)
        images[id] = nil
        shapes[id] = nil
        CardFiles.writeStampFile(file, id: id)
        var next = revisions
        next[id, default: 0] += 1
        revisions = next
    }
}
