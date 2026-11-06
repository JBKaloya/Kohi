import SwiftUI

extension CoffeeCard {
    /// Card-era home notes with no brew behind them. Nothing new writes these.
    var homeNotes: [Tasting] {
        tastings.filter { tasting in
            guard case .home(let brewID) = tasting.context else { return false }
            if let brewID, brews.contains(where: { $0.id == brewID }) { return false }
            return true
        }
    }
}

/// The brews made at home, then the card-era home notes. Absent when there
/// are neither; the Brews tab shows its own empty state.
struct BrewsSection: View {
    let card: CoffeeCard
    let onSelectBrew: (Brew) -> Void
    var onAgain: ((Brew) -> Void)?
    var onCompare: ((Brew) -> Void)?
    var onDeleteBrew: ((Brew) -> Void)?
    var onRead: ((Brew) -> Void)?

    var body: some View {
        let notes = card.homeNotes
        if !card.brews.isEmpty || !notes.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text(Copy.brews)
                    .catalogueLabel()
                    .padding(.bottom, 4)
                if !card.brews.isEmpty {
                    BrewLog(
                        brews: card.brews,
                        onSelect: onSelectBrew,
                        onAgain: onAgain,
                        onCompare: onCompare,
                        onDelete: onDeleteBrew,
                        onRead: onRead
                    )
                }
                ForEach(notes) { tasting in
                    homeRow(tasting)
                }
            }
        }
    }

    private func homeRow(_ tasting: Tasting) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(CatalogueDate.happened(tasting.date))
                    .font(Typography.tag)
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 4)
                if let rating = tasting.rating {
                    RatingDots(rating: rating)
                }
            }
            TastingSummary(tasting: tasting)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Coffee-shop tastings linked to this card, with their average. Read-only
/// here; they are written in the Tastings tab. Absent when there are none.
struct TastedAtSection: View {
    /// Newest first.
    let tasted: [Tasting]
    let onOpenTasting: (Tasting) -> Void

    var body: some View {
        if !tasted.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(Copy.tastedAt)
                        .catalogueLabel()
                    Spacer()
                    if let line = TastingScore.line(tasted) {
                        Text(line)
                            .font(Typography.tag)
                            .foregroundStyle(Palette.inkMuted)
                    }
                }
                .padding(.bottom, 4)
                TastingList(tastings: tasted, showsCoffee: false, onSelect: onOpenTasting)
            }
        }
    }
}
