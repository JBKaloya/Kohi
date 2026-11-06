import Foundation

/// The two halves of a card: what the coffee is, and what you made of it.
enum CardDetailTab: String, CaseIterable, Identifiable, Sendable {
    case coffee
    case brews

    var id: String { rawValue }

    /// "Brews 4" once there is a brew to count. The tab is there either way.
    func label(brewCount: Int) -> String {
        switch self {
        case .coffee: Copy.coffee
        case .brews: brewCount > 0 ? "\(Copy.brews) \(brewCount)" : Copy.brews
        }
    }
}

/// One block of the card detail, in reading order.
enum CardDetailSection: Hashable, Sendable {
    // Coffee
    case notes
    case onTheWheel
    case caption
    case originals
    case recipes
    case kitPrompt
    case attachments
    case personalNote
    case actions
    // Brews
    case profile
    case brewLog
    case noBrews
    case tastedAt
}

/// Which blocks each tab shows, and in what order. Pure, so the split between
/// the tabs is tested without rendering: no brew block on Coffee, no card
/// action on Brews.
enum CardDetailSections {
    struct Flags: Equatable, Sendable {
        /// A printed or suggested recipe to show under Suggested.
        var hasRecipe = false
        var kitIsEmpty = false
        var showsProfile = false
        var tastedCount = 0
        var isIngestingAttachment = false
    }

    static func ordered(for tab: CardDetailTab, card: CoffeeCard, flags: Flags) -> [CardDetailSection] {
        var sections: [CardDetailSection] = []
        switch tab {
        case .coffee:
            if !card.tastingNotes.isEmpty { sections.append(.notes) }
            if !card.declaredFlavors.isEmpty { sections.append(.onTheWheel) }
            sections.append(.caption)
            if !card.originalFields.isEmpty { sections.append(.originals) }
            if flags.hasRecipe { sections.append(.recipes) }
            if flags.kitIsEmpty { sections.append(.kitPrompt) }
            if !card.attachments.isEmpty || flags.isIngestingAttachment { sections.append(.attachments) }
            if !card.personalNotes.trimmingCharacters(in: .whitespaces).isEmpty { sections.append(.personalNote) }
            sections.append(.actions)
        case .brews:
            let hasBrews = !card.brews.isEmpty || !card.homeNotes.isEmpty
            if flags.showsProfile && card.brews.count >= 2 { sections.append(.profile) }
            sections.append(hasBrews ? .brewLog : .noBrews)
            if flags.tastedCount > 0 { sections.append(.tastedAt) }
        }
        return sections
    }
}
