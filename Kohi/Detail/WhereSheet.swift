import CoreLocation
import SwiftUI

/// Where a tasting happened. Nearby places first — yours, the seed's, then
/// Apple Maps — then your earlier places, then search, then a name typed by
/// hand. A tasting always has a place, so adding one by hand is always there.
struct WhereSheet: View {
    /// The coffee's roaster when it is already known, to raise a place that
    /// serves it. Usually empty: the place comes first.
    var roaster: String = ""
    var nearby: NearbyPlaces
    /// Snapshot and tests pass a list instead of asking for a fix.
    var previewSuggestions: [SeedPlace]? = nil
    var requestsLocation = true
    let onPick: (Place, String?) -> Void

    @Environment(PlaceIndex.self) private var places
    @Environment(TastingStore.self) private var tastings
    @Environment(\.dismiss) private var dismiss
    @State private var isSearching = false
    @State private var searchedPlace: Place?
    @State private var searchedPlaceID: String?
    @State private var isTyping = false
    @State private var typedName = ""
    @State private var typedAddress = ""
    @FocusState private var typedFocus: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(nearby.isDenied ? Copy.placeDenied : Copy.placePermission)
                        .font(Typography.subtitle)
                        .foregroundStyle(Palette.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)

                    if !suggestions.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(suggestions) { suggestion in
                                chip(suggestion.place.name, tag: suggestion.caption) {
                                    pick(suggestion.place, suggestion.placeID)
                                }
                            }
                        }
                    }

                    if !remembered.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(Copy.yours)
                                .catalogueLabel()
                                .padding(.bottom, 4)
                            ForEach(remembered, id: \.id) { row in
                                Button {
                                    pick(row.place, row.placeID)
                                } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(row.place.name)
                                            .font(Typography.value)
                                            .foregroundStyle(Palette.ink)
                                        if !row.place.address.isEmpty {
                                            Text(row.place.address)
                                                .font(Typography.subtitle)
                                                .foregroundStyle(Palette.inkMuted)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 12)
                                }
                                .buttonStyle(.plain)
                                Rectangle().fill(Palette.hairline).frame(height: 1)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        row(Copy.placeOther) { isSearching = true }
                        Rectangle().fill(Palette.hairline).frame(height: 1)
                        row(Copy.addPlaceByHand) {
                            withAnimation(Motion.quick) { isTyping = true }
                            typedFocus = true
                        }
                        if isTyping { byHand }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 8)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .background(Palette.paper.ignoresSafeArea())
            .navigationTitle(Copy.placeTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.light, for: .navigationBar)
            .tint(Palette.ink)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationBackground(Palette.paper)
        .sheet(isPresented: $isSearching) {
            PlaceSearchView(place: $searchedPlace, placeID: $searchedPlaceID)
        }
        .onChange(of: searchedPlace) { _, place in
            guard let place else { return }
            pick(place, searchedPlaceID)
        }
        .task {
            guard requestsLocation, previewSuggestions == nil else { return }
            nearby.start()
        }
        .task(id: nearby.coordinate?.latitude) {
            guard previewSuggestions == nil else { return }
            places.beginGeocoding()
            await nearby.searchCafes()
        }
    }

    private var suggestions: [PlaceSuggestion] {
        nearby.suggestions(
            roaster: roaster,
            index: places,
            tastings: tastings.tastings,
            preview: previewSuggestions
        )
    }

    private struct Remembered: Identifiable {
        let place: Place
        let placeID: String?
        var id: String { placeID ?? place.mapItemID ?? "\(SeedPlace.fold(place.name))|\(SeedPlace.fold(place.address))" }
    }

    /// Earlier places that are not already offered above.
    private var remembered: [Remembered] {
        let offered = suggestions
        return TastingPlaces.remembered(in: tastings.tastings).compactMap { row in
            if offered.contains(where: { PlaceKey.same($0.place, $0.placeID, row.place, row.placeID) }) {
                return nil
            }
            return Remembered(place: row.place, placeID: row.placeID)
        }
        .prefix(6)
        .map { $0 }
    }

    private var byHand: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField(Copy.placeNamePrompt, text: $typedName)
                .font(Typography.value)
                .foregroundStyle(Palette.ink)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .focused($typedFocus)
                .submitLabel(.next)
            TextField(Copy.placeAddressPrompt, text: $typedAddress)
                .font(Typography.subtitle)
                .foregroundStyle(Palette.ink)
                .submitLabel(.done)
                .onSubmit(addByHand)
            if typedName.trimmingCharacters(in: .whitespaces).count >= 2 {
                Button(action: addByHand) {
                    Text(Copy.addNamed(typedName.trimmingCharacters(in: .whitespaces)))
                        .catalogueLabel()
                        .foregroundStyle(Palette.ink)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 14)
        .transition(.opacity)
    }

    /// Saved as a custom place, so it comes back in search.
    private func addByHand() {
        let name = typedName.trimmingCharacters(in: .whitespaces)
        guard name.count >= 2 else { return }
        let address = typedAddress.trimmingCharacters(in: .whitespaces)
        let typed = Place(name: name, address: address, latitude: 0, longitude: 0)
        places.addCustom(typed)
        pick(typed, nil)
    }

    private func pick(_ place: Place, _ placeID: String?) {
        onPick(place, placeID)
        dismiss()
    }

    private func row(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Typography.value)
                .foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    private func chip(_ title: String, tag: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(Typography.tag)
                    .foregroundStyle(Palette.ink)
                if let tag {
                    Text(tag)
                        .font(Typography.tag)
                        .foregroundStyle(Palette.inkMuted)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .overlay(Capsule().stroke(Palette.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
