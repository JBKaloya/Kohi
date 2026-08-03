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

        let coordinate = item.location.coordinate
        return Place(
            name: item.name ?? completion.title,
            address: completion.subtitle,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
    }
}

/// Minimal search sheet: a field, a list, and nothing else.
struct PlaceSearchView: View {
    @Binding var place: Place?

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
                        ForEach(search.results, id: \.self) { result in
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

                            Rectangle().fill(Palette.hairline).frame(height: 1)
                                .padding(.leading, 24)
                        }
                    }
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
        }
    }

    private func choose(_ completion: MKLocalSearchCompletion) async {
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
}
