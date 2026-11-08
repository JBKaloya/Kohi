import CoreLocation
import MapKit
import Observation
import os

/// Where you might be standing, for a tasting.
///
/// One fix, shared by the capture and the place sheet, never in the
/// background. The order is the PRD's: places from your own tastings, then the
/// bundled seed, then cafés Apple Maps knows within 300 metres. A shared
/// backend source would slot in before Maps.
@Observable
final class NearbyPlaces {
    static let yoursRadius: CLLocationDistance = 150
    static let mapsRadius: CLLocationDistance = 300

    let locator: PlaceLocator
    private(set) var cafes: [Place] = []
    @ObservationIgnored private var searchedAround: CLLocationCoordinate2D?

    init(accuracy: CLLocationAccuracy = kCLLocationAccuracyHundredMeters) {
        locator = PlaceLocator(accuracy: accuracy)
    }

    var coordinate: CLLocationCoordinate2D? { locator.coordinate }
    var isDenied: Bool { locator.isDenied }

    func start() { locator.start() }

    /// Maps cafés around the fix, once per fix.
    func searchCafes() async {
        guard let coordinate else { return }
        Task { await LocalCurrency.shared.learn(from: coordinate) }
        if let searchedAround,
           CLLocation(latitude: searchedAround.latitude, longitude: searchedAround.longitude)
            .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) < 50 {
            return
        }
        searchedAround = coordinate
        let request = MKLocalPointsOfInterestRequest(center: coordinate, radius: Self.mapsRadius)
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.cafe, .bakery])
        do {
            let response = try await MKLocalSearch(request: request).start()
            let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            cafes = response.mapItems
                .map { Place(item: $0) }
                .filter { !$0.name.isEmpty }
                .sorted { Self.distance($0, from: origin) < Self.distance($1, from: origin) }
        } catch {
            Log.app.notice("nearby cafés: \(error.localizedDescription)")
        }
    }

    func suggestions(
        roaster: String,
        index: PlaceIndex,
        tastings: [Tasting],
        preview: [SeedPlace]? = nil
    ) -> [PlaceSuggestion] {
        var result: [PlaceSuggestion] = []
        func add(_ suggestion: PlaceSuggestion) {
            guard !result.contains(where: {
                PlaceKey.same($0.place, $0.placeID, suggestion.place, suggestion.placeID)
                    || ($0.placeID != nil && $0.placeID == suggestion.placeID)
            }) else { return }
            result.append(suggestion)
        }

        if let coordinate {
            let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let yours = TastingPlaces.remembered(in: tastings)
                .filter { $0.place.hasResolvedCoordinate }
                .map { ($0, Self.distance($0.place, from: origin)) }
                .filter { $0.1 <= Self.yoursRadius }
                .sorted { $0.1 < $1.1 }
            for (row, _) in yours {
                add(PlaceSuggestion(place: row.place, placeID: row.placeID, source: .yours))
            }
        }

        let seeds = preview ?? TastingPlaces.suggest(roaster: roaster, index: index, from: coordinate)
        for seed in seeds {
            let stored = index.coordinate(for: seed.id)
            add(PlaceSuggestion(
                place: Place(
                    name: seed.name,
                    address: seed.address,
                    latitude: stored?.latitude ?? 0,
                    longitude: stored?.longitude ?? 0,
                    city: seed.city
                ),
                placeID: seed.id,
                source: .seed,
                tag: seed.statusTag
            ))
        }

        for cafe in cafes.prefix(5) {
            add(PlaceSuggestion(place: cafe, placeID: nil, source: .maps))
        }
        return result
    }

    private static func distance(_ place: Place, from origin: CLLocation) -> CLLocationDistance {
        guard place.hasResolvedCoordinate else { return .greatestFiniteMagnitude }
        return origin.distance(from: CLLocation(latitude: place.latitude, longitude: place.longitude))
    }
}

nonisolated struct PlaceSuggestion: Identifiable, Hashable, Sendable {
    enum Source: Hashable, Sendable {
        case yours
        case seed
        case maps
    }

    let place: Place
    let placeID: String?
    let source: Source
    var tag: String?

    var id: String { placeID ?? place.mapItemID ?? "\(place.name)|\(place.latitude)|\(place.longitude)" }

    var caption: String {
        switch source {
        case .yours: Copy.yourVisit
        case .seed: tag ?? Copy.servedHere
        case .maps: Copy.maps
        }
    }
}
