import SwiftUI

/// Renders a mosaic tile once and keeps the PNG. The ground is drawn off the main
/// thread in CoreGraphics; the label and the sticker go on top through ImageRenderer.
@MainActor
final class CardComposer {
    static let shared = CardComposer()

    /// Canonical tile width. The mosaic scales the PNG down to the column.
    static let tileWidth: CGFloat = 360
    static let tileScale: CGFloat = 3

    var defaults: UserDefaults = .standard

    private(set) var renderCount = 0
    private var tail: Task<Void, Never>?
    private let memory = NSCache<NSString, CacheBox>()
    private let fields = NSCache<NSString, CacheBox>()

    func resetCountForTesting() {
        renderCount = 0
    }

    func clearMemoryForTesting() {
        memory.removeAllObjects()
        fields.removeAllObjects()
    }

    /// Cache hit does not increment `renderCount`.
    func tile(for card: CoffeeCard) async -> CGImage? {
        let token = token(for: card)
        if let hit = memory.object(forKey: token as NSString)?.image {
            return hit
        }
        if let disk = CardFiles.readKohi(id: card.id, token: token) {
            memory.setObject(CacheBox(disk), forKey: token as NSString)
            return disk
        }

        let previous = tail
        let task = Task { @MainActor in
            _ = await previous?.value
            await Task.yield()
            guard !Task.isCancelled else { return }
            if self.memory.object(forKey: token as NSString) != nil { return }
            guard let image = await self.draw(card) else { return }
            self.renderCount += 1
            self.memory.setObject(CacheBox(image), forKey: token as NSString)
            CardFiles.writeKohi(image, id: card.id, token: token)
            CardFiles.removeStaleKohi(id: card.id, keeping: token)
        }
        tail = task
        _ = await task.value
        return memory.object(forKey: token as NSString)?.image
    }

    func token(for card: CoffeeCard) -> String {
        let file = CardFiles.loadStampFile(card.id)
        let art = CardArt.make(card, ink: file)
        return KohiCardContent.make(card, art: art).cacheToken(
            symbol: Self.symbolSignature(file, art: art),
            layout: CardLayout.stored(for: card.id, defaults),
            density: .tile
        )
    }

    /// The field alone at tile size: what a tile shows while its render is queued.
    func placeholderField(for card: CoffeeCard) -> (image: CGImage, tone: CardBackdrop.TextTone)? {
        let key = token(for: card) as NSString
        if let hit = fields.object(forKey: key) { return (hit.image, hit.tone) }
        let art = CardArt.make(card, ink: CardFiles.loadStampFile(card.id))
        guard let (low, tone) = CardBackdrop.lowField(art) else { return nil }
        fields.setObject(CacheBox(low, tone: tone), forKey: key)
        return (low, tone)
    }

    /// What the ground shows of the symbol, and from which measurement. Empty for nothing.
    nonisolated static func symbolSignature(_ file: StampFile?, art: CardArt) -> String {
        guard let file, let stamp = file.stamp else { return "" }
        let treatment = file.treatment(draw: art.symbolDraws[4])
        guard treatment != .none else { return "" }
        let r = stamp.rect
        return [
            treatment.rawValue,
            String(stamp.version),
            String(file.vectorVersion ?? 0),
            String(format: "%.4f,%.4f,%.4f,%.4f", r.minX, r.minY, r.width, r.height),
        ].joined(separator: "|")
    }

    /// The symbol as stored for one card: the shape when current, else the soft bitmap.
    nonisolated static func mark(for id: UUID, file: StampFile?) -> MarkSource? {
        guard let file, file.stamp != nil, file.stamp?.source != .library else { return nil }
        if file.vectorVersion == MarkShape.version, let shape = CardFiles.readStampShape(id) {
            return .shape(shape)
        }
        return CardFiles.readStamp(id).map { .bitmap($0) }
    }

    private func draw(_ card: CoffeeCard) async -> CGImage? {
        let id = card.id
        let file = CardFiles.loadStampFile(id)
        let art = CardArt.make(card, ink: file)
        let content = KohiCardContent.make(card, art: art)
        let layout = CardLayout.stored(for: id, defaults)
        let treatment = file?.treatment(draw: art.symbolDraws[4]) ?? .none
        let pixels = CGSize(
            width: Self.tileWidth * Self.tileScale,
            height: Self.tileWidth * Self.tileScale / CardTileLayout.aspectRatio
        )
        let rendered = await Task.detached(priority: .utility) {
            let mark = treatment == .none ? nil : Self.mark(for: id, file: file)
            return CardBackdrop.render(art, mark: mark, treatment: treatment, size: pixels)
        }.value

        let view = KohiCard(
            content: content,
            density: .tile,
            width: Self.tileWidth,
            layout: layout,
            backdrop: rendered?.image,
            textTone: rendered?.textTone ?? .ink
        )
        let renderer = ImageRenderer(content: view)
        renderer.scale = Self.tileScale
        renderer.isOpaque = false
        renderer.proposedSize = ProposedViewSize(
            width: Self.tileWidth,
            height: Self.tileWidth / CardTileLayout.aspectRatio
        )
        return renderer.cgImage
    }
}

private final class CacheBox: NSObject {
    let image: CGImage
    let tone: CardBackdrop.TextTone
    init(_ image: CGImage, tone: CardBackdrop.TextTone = .ink) {
        self.image = image
        self.tone = tone
    }
}
