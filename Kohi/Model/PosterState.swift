import Foundation

/// Lifecycle of a generated poster image for a card.
nonisolated enum PosterState: String, Codable, Hashable, Sendable {
    case none
    case pending
    case ready
    case failed
}

/// Geometry of the AI flyer. Kept in one place so the grid, the detail view,
/// and the generator all agree.
nonisolated enum PosterLayout {
    /// Width over height. 4:5 portrait, like a small printed card.
    static let aspectRatio = 4.0 / 5.0
}
