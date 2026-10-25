import SwiftUI

/// What a card shows of the cups it went into: the brews made at home, then
/// the coffee-shop tastings linked to it. Tastings are read-only here; they
/// are written in the Tastings tab. An empty group is absent.
struct TastingsBlock: View {
    let card: CoffeeCard
    /// Coffee-shop tastings linked to this card, newest first.
    let tasted: [Tasting]
    let onSelectBrew: (Brew) -> Void
    var onAgain: ((Brew) -> Void)?
    var onCompare: ((Brew) -> Void)?
    var onDeleteBrew: ((Brew) -> Void)?
    var onRead: ((Brew) -> Void)?
    let onOpenTasting: (Tasting) -> Void

    /// Card-era home notes with no brew behind them. Nothing new writes these.
    private var homeNotes: [Tasting] {
        card.tastings.filter { tasting in
            guard case .home(let brewID) = tasting.context else { return false }
            if let brewID, card.brews.contains(where: { $0.id == brewID }) { return false }
            return true
        }
    }

    private var showsBrews: Bool { !card.brews.isEmpty || !homeNotes.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if showsBrews {
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
                    ForEach(homeNotes) { tasting in
                        homeRow(tasting)
                    }
                }
            }

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

/// "4.0 · 3 tastings". Nil when nothing was scored.
enum TastingScore {
    static func line(_ tastings: [Tasting]) -> String? {
        let ratings = tastings.compactMap(\.rating)
        guard !ratings.isEmpty else { return nil }
        let average = Double(ratings.reduce(0, +)) / Double(ratings.count)
        let noun = ratings.count == 1 ? "tasting" : "tastings"
        return String(format: "%.1f", average) + " · \(ratings.count) \(noun)"
    }
}

/// Coffee-shop tastings as rows. Each opens the tasting.
struct TastingList: View {
    let tastings: [Tasting]
    /// The Tastings tab leads with the coffee; a card already is the coffee.
    var showsCoffee = true
    var showsPlace = true
    let onSelect: (Tasting) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(tastings.enumerated()), id: \.element.id) { index, tasting in
                if index > 0 {
                    Rectangle()
                        .fill(Palette.hairline)
                        .frame(height: 1)
                }
                Button { onSelect(tasting) } label: {
                    TastingLine(tasting: tasting, showsCoffee: showsCoffee, showsPlace: showsPlace)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// One tasting: the coffee and its roaster, the shop, the date, the method,
/// the score and the price when there is one.
struct TastingLine: View {
    let tasting: Tasting
    var showsCoffee = true
    var showsPlace = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(showsCoffee ? tasting.coffeeName() : (tasting.place?.name ?? ""))
                    .font(Typography.value)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let rating = tasting.rating {
                    RatingDots(rating: rating)
                }
            }
            if let line = context {
                Text(line)
                    .font(Typography.tag)
                    .foregroundStyle(Palette.inkMuted)
                    .lineLimit(1)
            }
            TastingSummary(tasting: tasting)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var context: String? {
        var parts: [String] = []
        if showsCoffee {
            let roaster = tasting.coffee.roaster.trimmingCharacters(in: .whitespaces)
            if !roaster.isEmpty { parts.append(roaster) }
            if showsPlace, let place = tasting.place?.name { parts.append(place) }
        }
        parts.append(CatalogueDate.happened(tasting.date))
        if let method = tasting.methodLine { parts.append(method) }
        if let price = tasting.price { parts.append(price.formatted) }
        return parts.joined(separator: " · ")
    }
}

/// What a row says about the cup beyond its score: the flavours, how many
/// axes were scored, and the note.
struct TastingSummary: View {
    let tasting: Tasting

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let line = detail {
                Text(line)
                    .font(Typography.tag)
                    .foregroundStyle(Palette.inkMuted)
                    .lineLimit(1)
            }
            if let note = tasting.note, !note.isEmpty {
                Text(note)
                    .font(Typography.tag)
                    .foregroundStyle(Palette.inkMuted)
                    .lineLimit(2)
            }
        }
    }

    private var detail: String? {
        var parts = tasting.flavors.prefix(3).map(\.displayName)
        if !tasting.taste.isEmpty {
            parts.append("\(tasting.taste.scoredAxes.count) of 7")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
