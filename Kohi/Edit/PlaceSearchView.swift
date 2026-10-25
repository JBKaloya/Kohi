import MapKit
import Observation
import SwiftUI

/// Typeahead over Apple Maps, biased toward wherever you are if you have let
/// the app know. Without a fix it still works, just unranked by distance —
/// which matters, because "Coffee Collective" exists in a dozen cities.
@Observable
final class PlaceSearch: NSObject, MKLocalSearchCompleterDelegate {
    var query = "" {
        didSet {
            guard query != oldValue else { return }
            completer.queryFragment = query
            if query.isEmpty { results = [] }
        }
    }

    private(set) var results: [MKLocalSearchCompletion] = []

    /// The box searches are biased to, once there is a fix.
    private var region: MKCoordinateRegion?

    /// Wide enough to cover a city and its suburbs, narrow enough that the shop
    /// down the road outranks the one on another continent.
    private static let searchRadius: CLLocationDistance = 30_000

    @ObservationIgnored private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.resultTypes = [.pointOfInterest, .address]
        completer.delegate = self
    }

    /// Re-runs the current query against the new region, so results reorder the
    /// moment the fix lands rather than on the next keystroke.
    func center(on coordinate: CLLocationCoordinate2D) {
        let region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: Self.searchRadius,
            longitudinalMeters: Self.searchRadius
        )
        self.region = region
        completer.region = region
        if !query.isEmpty {
            completer.queryFragment = query
        }
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        results = completer.results
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: any Error) {
        // Offline is a normal state for this app, not an error worth surfacing.
        results = []
    }

    /// Turns a suggestion into something worth storing.
    func resolve(_ completion: MKLocalSearchCompletion) async -> Place? {
        let request = MKLocalSearch.Request(completion: completion)
        if let region { request.region = region }
        guard
            let response = try? await MKLocalSearch(request: request).start(),
            let item = response.mapItems.first
        else { return nil }

        return Place(item: item, fallbackName: completion.title, address: completion.subtitle)
    }
}

extension Place {
    /// A Maps result, with the identifier that tells two same-named cafés apart.
    init(item: MKMapItem, fallbackName: String = "", address: String? = nil) {
        let coordinate: CLLocationCoordinate2D
        if #available(iOS 26, *) {
            coordinate = item.location.coordinate
        } else {
            coordinate = item.placemark.coordinate
        }
        let placemark = item.placemark
        let street = [placemark.subThoroughfare, placemark.thoroughfare]
            .compactMap { $0 }
            .joined(separator: " ")
        self.init(
            name: item.name ?? fallbackName,
            address: address ?? street,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            mapItemID: item.identifier?.rawValue,
            city: placemark.locality,
            country: placemark.country
        )
    }
}

/// Paris places from the seed, then Apple Maps, then a name typed by hand.
struct PlaceSearchView: View {
    @Binding var place: Place?
    @Binding var placeID: String?

    @Environment(PlaceIndex.self) private var places
    @Environment(TastingStore.self) private var tastings
    @Environment(\.dismiss) private var dismiss
    @State private var search = PlaceSearch()
    @State private var locator = PlaceLocator()
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    TextField("Coffee shop or roaster", text: Bindable(search).query)
                        .font(Typography.value)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .focused($isFocused)

                    // Quiet confirmation that the list is ordered by how close
                    // things are, rather than a permission prompt with no
                    // visible consequence.
                    if locator.coordinate != nil {
                        Text("Nearby")
                            .catalogueLabel()
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .animation(Motion.quick, value: locator.coordinate == nil)

                Rectangle().fill(Palette.hairline).frame(height: 1)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if showsNamedAdd {
                            namedAddRow
                        }
                        yoursSection
                        parisSections

                        if !search.results.isEmpty {
                            Text(Copy.maps)
                                .catalogueLabel()
                                .padding(.horizontal, 24)
                                .padding(.top, 22)
                                .padding(.bottom, 8)
                            ForEach(search.results, id: \.self) { result in
                                mapRow(result)
                            }
                        }

                    }
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
            }
            .background(Palette.paper.ignoresSafeArea())
            .navigationTitle("Place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if place != nil {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Remove") {
                            place = nil
                            placeID = nil
                            dismiss()
                        }
                    }
                }
            }
        }
        .task {
            isFocused = true
            locator.start()
        }
        .onChange(of: locator.coordinate?.latitude) { _, _ in
            guard let coordinate = locator.coordinate else { return }
            search.center(on: coordinate)
            places.beginGeocoding()
        }
    }

    private var manualName: String {
        search.query.trimmingCharacters(in: .whitespaces)
    }

    /// The typed name is worth keeping when nothing already has that exact name.
    private var showsNamedAdd: Bool {
        let name = manualName
        guard name.count >= 2 else { return false }
        let key = SeedPlace.fold(name)
        if places.custom(matching: "").contains(where: { SeedPlace.fold($0.name) == key }) {
            return false
        }
        if places.pickable.contains(where: { SeedPlace.fold($0.name) == key }) {
            return false
        }
        if search.results.contains(where: { SeedPlace.fold($0.title) == key }) {
            return false
        }
        if TastingPlaces.remembered(in: tastings.all).contains(where: { SeedPlace.fold($0.place.name) == key }) {
            return false
        }
        return true
    }

    private var namedAddRow: some View {
        Button(action: addManually) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                Text(Copy.addNamed(manualName))
                    .font(Typography.value)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Spacer(minLength: 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .buttonStyle(.plain)
    }

    private struct YoursRow: Identifiable {
        var place: Place
        var placeID: String?
        var id: String { placeID ?? SeedPlace.fold(place.name) }
    }

    private var yours: [YoursRow] {
        var seen: Set<String> = []
        var rows: [YoursRow] = []
        func add(_ place: Place, _ placeID: String?) {
            let key = placeID ?? SeedPlace.fold(place.name)
            guard !key.isEmpty, seen.insert(key).inserted else { return }
            rows.append(YoursRow(place: place, placeID: placeID))
        }
        for place in places.custom(matching: search.query) {
            add(place, nil)
        }
        for row in TastingPlaces.remembered(in: tastings.all, matching: search.query) {
            add(row.place, row.placeID)
        }
        return rows
    }

    @ViewBuilder
    private var yoursSection: some View {
        let rows = yours
        if !rows.isEmpty {
            Text(Copy.yours)
                .catalogueLabel()
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 4)
            ForEach(rows) { row in
                Button {
                    place = row.place
                    placeID = row.placeID
                    dismiss()
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
                    .padding(.horizontal, 24)
                    .padding(.vertical, 13)
                }
                .buttonStyle(.plain)
                Rectangle().fill(Palette.hairline).frame(height: 1)
                    .padding(.leading, 24)
            }
        }
    }

    @ViewBuilder
    private var parisSections: some View {
        let pool = places.pickable(matching: search.query)
        let nearby = locator.coordinate.map { places.nearby(pool, from: $0) } ?? []
        let nearbyIDs = Set(nearby.map(\.id))
        let rest = pool.filter { !nearbyIDs.contains($0.id) }
        if !pool.isEmpty {
            Text(Copy.fromSpecialtyCoffeeParis(places.places.first?.fetchedAt ?? ""))
                .font(Typography.tag)
                .foregroundStyle(Palette.inkMuted)
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 4)
        }
        if manualName.isEmpty {
            if !nearby.isEmpty {
                placeSection("Nearby", places: nearby)
            }
            ForEach(places.byArrondissement(rest), id: \.title) { group in
                placeSection(group.title, places: group.places)
            }
        } else if !pool.isEmpty {
            placeSection("Paris", places: nearby + rest)
        }
    }

    private func placeSection(_ title: String, places rows: [SeedPlace]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .catalogueLabel()
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 4)
            ForEach(rows) { row in
                Button {
                    choose(row)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.name)
                            .font(Typography.value)
                            .foregroundStyle(Palette.ink)
                        if !row.address.isEmpty {
                            Text(row.address)
                                .font(Typography.subtitle)
                                .foregroundStyle(Palette.inkMuted)
                        }
                        if let tag = row.statusTag {
                            Text(tag)
                                .font(Typography.tag)
                                .foregroundStyle(Palette.inkMuted)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 13)
                }
                .buttonStyle(.plain)
                Rectangle().fill(Palette.hairline).frame(height: 1)
                    .padding(.leading, 24)
            }
        }
    }

    private func mapRow(_ result: MKLocalSearchCompletion) -> some View {
        Button {
            Task { await choose(result) }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(result.title)
                    .font(Typography.value)
                    .foregroundStyle(Palette.ink)
                if !result.subtitle.isEmpty {
                    Text(result.subtitle)
                        .font(Typography.subtitle)
                        .foregroundStyle(Palette.inkMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 13)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.hairline).frame(height: 1)
                .padding(.leading, 24)
        }
    }

    private func choose(_ seed: SeedPlace) {
        Task {
            let coordinate = await places.geocode(seed)
            placeID = seed.id
            place = Place(
                name: seed.name,
                address: seed.address,
                latitude: coordinate?.latitude ?? 0,
                longitude: coordinate?.longitude ?? 0
            )
            dismiss()
        }
    }

    private func choose(_ completion: MKLocalSearchCompletion) async {
        placeID = nil
        if let resolved = await search.resolve(completion) {
            place = resolved
        } else {
            // Offline, or the lookup failed. Keeping the name is better than
            // nothing and the coordinates were never the point.
            place = Place(
                name: completion.title,
                address: completion.subtitle,
                latitude: 0,
                longitude: 0
            )
        }
        dismiss()
    }

    private func addManually() {
        guard manualName.count >= 2 else { return }
        placeID = nil
        let created = Place(name: manualName, address: "", latitude: 0, longitude: 0)
        places.addCustom(created)
        place = created
        dismiss()
    }
}
