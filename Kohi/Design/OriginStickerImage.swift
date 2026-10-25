import Foundation

/// One country, one sticker, always the same. Without a country the card wears the seal
/// of its process; without either, nothing.
nonisolated enum OriginStickerImage {
    /// Bump when the PNGs in `OriginStickers.xcassets` are rerendered.
    static let catalogueVersion = 1

    static func assetName(country: String, process: String) -> String? {
        if let iso = OriginCode.alpha2(for: country) {
            return "Stickers/origin-\(iso.lowercased())"
        }
        if let seal = Terroir.classify(process: process).sealKey {
            return "Stickers/seal-\(seal)"
        }
        return nil
    }

    static func assetName(for card: CoffeeCard) -> String? {
        assetName(country: card.country, process: card.process)
    }
}
