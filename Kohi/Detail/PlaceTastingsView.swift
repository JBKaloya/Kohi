import SwiftUI

/// One venue: where it is, how often you went, and every coffee had there.
/// No score for the place itself — the cups are what was rated.
struct PlaceTastingsView: View {
    let place: Place
    let placeID: String?

    @Environment(TastingStore.self) private var tastings
    @Environment(PlaceIndex.self) private var places
    @Environment(\.openURL) private var openURL
    @State private var openedTasting: Tasting?

    private var group: PlaceGroup? {
        PlaceKey.group(tastings.tastings).first {
            PlaceKey.same($0.place, $0.placeID, place, placeID)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(place.name)
                        .font(Typography.title)
                        .foregroundStyle(Palette.ink)
                    if let address = addressLine {
                        Text(address)
                            .font(Typography.subtitle)
                            .foregroundStyle(Palette.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(provenance)
                        .catalogueLabel()
                }

                HStack(spacing: 22) {
                    if let group {
                        Text(counts(group))
                            .font(Typography.tag)
                            .foregroundStyle(Palette.inkMuted)
                    }
                    Spacer(minLength: 0)
                    Button { openURL(place.appleMapsURL) } label: {
                        Text(Copy.maps).catalogueLabel()
                    }
                    .buttonStyle(.plain)
                }

                TastingList(
                    tastings: group?.tastings ?? [],
                    showsPlace: false,
                    onSelect: { openedTasting = $0 }
                )
            }
            .padding(.horizontal, 28)
            .padding(.top, 12)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .background(Palette.paper.ignoresSafeArea())
        .navigationTitle(place.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $openedTasting) { tasting in
            TastingDetailView(tastingID: tasting.id, opensPlace: false)
        }
    }

    private var addressLine: String? {
        let parts = [place.address, place.city ?? "", place.country ?? ""]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var seen = Set<String>()
        let unique = parts.filter { part in
            !parts.contains { $0 != part && $0.localizedCaseInsensitiveContains(part) } && seen.insert(part).inserted
        }
        return unique.isEmpty ? nil : unique.joined(separator: ", ")
    }

    private func counts(_ group: PlaceGroup) -> String {
        let visits = group.visits == 1 ? "1 visit" : "\(group.visits) visits"
        let coffees = group.coffees == 1 ? "1 coffee" : "\(group.coffees) coffees"
        return "\(visits) · \(coffees)"
    }

    private var provenance: String {
        if let placeID, let seed = places.place(id: placeID) {
            return Copy.fromSpecialtyCoffeeParis(seed.fetchedAt)
        }
        return Copy.yourVisit
    }
}

/// Identity for pushing a venue.
struct OpenedPlace: Identifiable, Hashable {
    let place: Place
    let placeID: String?

    var id: String { placeID ?? place.mapItemID ?? "user:\(SeedPlace.fold(place.name)):\(place.latitude),\(place.longitude)" }
}
