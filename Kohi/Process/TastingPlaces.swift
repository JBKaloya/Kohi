import CoreLocation
import Foundation

/// Which places to offer when a coffee was drunk out.
///
/// Three open places within 150 metres, nearest first, with a place that
/// serves this coffee's roaster raised above the others. Closed places never
/// appear. No fix means no suggestion: the search still works.
enum TastingPlaces {
    static let radius: CLLocationDistance = 150
    static let limit = 3

    static func suggest(
        card: CoffeeCard,
        index: PlaceIndex,
        from coordinate: CLLocationCoordinate2D?,
        roasterSlug: String? = nil
    ) -> [SeedPlace] {
        suggest(roaster: card.roaster, index: index, from: coordinate, roasterSlug: roasterSlug)
    }

    /// `roaster` raises a place that serves it. Empty when the coffee is not
    /// known yet, which is the usual case: the place comes first.
    static func suggest(
        roaster: String,
        index: PlaceIndex,
        from coordinate: CLLocationCoordinate2D?,
        roasterSlug: String? = nil
    ) -> [SeedPlace] {
        guard let coordinate else { return [] }
        let slug = roasterSlug ?? slug(matching: roaster)
        let near = index.nearby(index.pickable, from: coordinate, within: radius)
        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return near
            .sorted { lhs, rhs in
                let leftServes = serves(slug, place: lhs, index: index)
                let rightServes = serves(slug, place: rhs, index: index)
                if leftServes != rightServes { return leftServes }
                return distance(lhs, from: origin, index: index)
                    < distance(rhs, from: origin, index: index)
            }
            .prefix(limit)
            .map { $0 }
    }

    /// Places from your own earlier tastings, most recent first, so a
    /// free-text café comes back the next time. A suggestion list, not an
    /// identity: two rows that would read and pick the same are shown once.
    static func remembered(
        in tastings: [Tasting],
        matching query: String = ""
    ) -> [(place: Place, placeID: String?)] {
        var seen: Set<String> = []
        var result: [(place: Place, placeID: String?)] = []
        let needle = SeedPlace.fold(query)
        for tasting in tastings.sorted(by: { $0.date > $1.date }) where !tasting.isDeleted {
            guard case .out(let place, let placeID) = tasting.context else { continue }
            let key = placeID ?? place.mapItemID
                ?? SeedPlace.fold(place.name) + "|" + SeedPlace.fold(place.address)
            guard key != "|", seen.insert(key).inserted else { continue }
            if !needle.isEmpty {
                let hay = SeedPlace.fold(place.name) + SeedPlace.fold(place.address)
                guard hay.contains(needle) else { continue }
            }
            result.append((place, placeID))
        }
        return result
    }

    /// The bundled slug for a roaster name, when the seed knows that spelling.
    static func slug(matching name: String) -> String? {
        let key = Roaster.fold(name)
        guard !key.isEmpty else { return nil }
        return ReferenceBase.roasterSeeds.first { seed in
            Roaster.fold(seed.name) == key
                || seed.aliases.contains { Roaster.fold($0) == key }
        }?.slug
    }

    private static func serves(_ slug: String?, place: SeedPlace, index: PlaceIndex) -> Bool {
        guard let slug else { return false }
        return index.servedRoasterIDs(for: place.id).contains(slug)
    }

    private static func distance(
        _ place: SeedPlace,
        from origin: CLLocation,
        index: PlaceIndex
    ) -> CLLocationDistance {
        guard let stored = index.coordinate(for: place.id) else {
            return .greatestFiniteMagnitude
        }
        let point = CLLocation(latitude: stored.latitude, longitude: stored.longitude)
        return origin.distance(from: point)
    }
}
