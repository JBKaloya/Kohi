import Foundation

/// Shared card geometry. The grid and the detail plate agree on this so a
/// pinch does not reflow the archive.
nonisolated enum CardTileLayout {
    /// Width over height. 4:5 portrait, like a small printed card.
    static let aspectRatio = 4.0 / 5.0
}
