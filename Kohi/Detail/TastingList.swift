import SwiftUI

/// "4.0 · 3 tastings". Nil when nothing was scored.
enum TastingScore {
    static func line(_ tastings: [Tasting]) -> String? {
        let ratings = tastings.compactMap(\.ratingHalves)
        guard let average = HalfRating.mean(ratings) else { return nil }
        let noun = ratings.count == 1 ? "tasting" : "tastings"
        return HalfRating.meanText(average) + " · \(ratings.count) \(noun)"
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
                if let halves = tasting.ratingHalves {
                    RatingDots(halves: halves)
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
