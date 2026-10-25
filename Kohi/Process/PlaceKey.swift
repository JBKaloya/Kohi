import CoreLocation
import Foundation

/// When two tastings happened at the same venue.
///
/// Never on the name alone: Paris has more than one "Café Lomi"-shaped name,
/// and a typed "the corner" is not every corner. In order: the seed slug, the
/// Maps identifier, then the folded name with both pins within 75 metres.
/// Anything else stays its own venue.
nonisolated enum PlaceKey {
    static let mergeRadius: CLLocationDistance = 75

    static func same(_ a: Place, _ aID: String?, _ b: Place, _ bID: String?) -> Bool {
        if let aID, let bID { return aID == bID }
        if let left = a.mapItemID, let right = b.mapItemID { return left == right }
        let leftName = SeedPlace.fold(a.name)
        guard !leftName.isEmpty, leftName == SeedPlace.fold(b.name) else { return false }
        guard a.hasResolvedCoordinate, b.hasResolvedCoordinate else { return false }
        let left = CLLocation(latitude: a.latitude, longitude: a.longitude)
        let right = CLLocation(latitude: b.latitude, longitude: b.longitude)
        return left.distance(from: right) <= mergeRadius
    }

    /// Tastings by venue, the most recently visited first.
    static func group(_ tastings: [Tasting]) -> [PlaceGroup] {
        var groups: [PlaceGroup] = []
        for tasting in tastings.sorted(by: { $0.date > $1.date }) {
            guard let place = tasting.place else { continue }
            if let index = groups.firstIndex(where: {
                same($0.place, $0.placeID, place, tasting.placeID)
            }) {
                groups[index].tastings.append(tasting)
            } else {
                groups.append(PlaceGroup(place: place, placeID: tasting.placeID, tastings: [tasting]))
            }
        }
        return groups
    }
}

/// One venue and every tasting had there.
nonisolated struct PlaceGroup: Identifiable, Hashable, Sendable {
    let place: Place
    let placeID: String?
    var tastings: [Tasting]

    var id: String {
        placeID ?? place.mapItemID ?? tastings.first?.id.uuidString ?? place.name
    }

    var visits: Int {
        Set(tastings.map { Calendar.current.startOfDay(for: $0.date) }).count
    }

    var coffees: Int {
        Set(tastings.map { SeedPlace.fold($0.coffee.name) }.filter { !$0.isEmpty }).count
    }

    var lastVisit: Date? { tastings.map(\.date).max() }
}
