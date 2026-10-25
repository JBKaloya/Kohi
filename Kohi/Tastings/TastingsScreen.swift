import SwiftUI

/// Coffees had in coffee shops, by coffee or by place.
///
/// Its own tab and its own store: nothing here needs a card on the shelf.
struct TastingsScreen: View {
    let onAdd: () -> Void
    @Binding var opened: Tasting?
    @Binding var openedPlace: PlaceGroup?

    @Environment(TastingStore.self) private var tastings
    @State private var rail: Rail = .coffees

    enum Rail: String, CaseIterable, Identifiable {
        case coffees
        case places

        var id: String { rawValue }

        var label: String {
            switch self {
            case .coffees: "Coffees"
            case .places: Copy.places
            }
        }
    }

    var body: some View {
        if tastings.isEmpty {
            empty
        } else {
            VStack(spacing: 0) {
                TabRail(tabs: Rail.allCases, selection: $rail, underline: .active, title: \.label)
                    .padding(.horizontal, 22)
                ScrollView {
                    switch rail {
                    case .coffees: coffees
                    case .places: placesList
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 18) {
            Text(Copy.tastingsEmpty)
                .font(Typography.subtitle)
                .foregroundStyle(Palette.inkMuted)
                .multilineTextAlignment(.center)
            Button(action: onAdd) {
                Text(Copy.addFirstTasting).catalogueLabel()
            }
            .buttonStyle(.plain)
            .touchTarget()
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var months: [(title: String, tastings: [Tasting])] {
        let sorted = tastings.tastings.sorted { $0.date > $1.date }
        var out: [(String, [Tasting])] = []
        for tasting in sorted {
            let title = CatalogueDate.month(tasting.date)
            if out.last?.0 == title {
                out[out.count - 1].1.append(tasting)
            } else {
                out.append((title, [tasting]))
            }
        }
        return out.map { (title: $0.0, tastings: $0.1) }
    }

    private var coffees: some View {
        LazyVStack(alignment: .leading, spacing: 26) {
            ForEach(months, id: \.title) { month in
                VStack(alignment: .leading, spacing: 4) {
                    Text(month.title).catalogueLabel()
                    TastingList(tastings: month.tastings) { opened = $0 }
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 18)
        .padding(.bottom, 160)
    }

    private var groups: [PlaceGroup] {
        PlaceKey.group(tastings.tastings)
            .sorted { ($0.lastVisit ?? .distantPast) > ($1.lastVisit ?? .distantPast) }
    }

    private var placesList: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                if index > 0 {
                    Rectangle().fill(Palette.hairline).frame(height: 1)
                }
                Button { openedPlace = group } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.place.name)
                            .font(Typography.value)
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                        Text(PlaceSummary.line(group))
                            .font(Typography.tag)
                            .foregroundStyle(Palette.inkMuted)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 18)
        .padding(.bottom, 160)
    }
}

/// "3 visits · 2 coffees · last Oct 12".
enum PlaceSummary {
    static func line(_ group: PlaceGroup) -> String {
        var parts = [
            group.visits == 1 ? "1 visit" : "\(group.visits) visits",
            group.coffees == 1 ? "1 coffee" : "\(group.coffees) coffees",
        ]
        if let last = group.lastVisit { parts.append(CatalogueDate.happened(last)) }
        if let city = group.place.city, !city.isEmpty { parts.append(city) }
        return parts.joined(separator: " · ")
    }
}
