import CoreLocation
import Foundation
import Observation

/// A geocoded point, kept beside the seed rather than inside it.
nonisolated struct PlaceCoordinate: Codable, Hashable, Sendable {
    var latitude: Double
    var longitude: Double
}

/// What this device has learned about the Paris places: coordinates, and which
/// roaster a café serves when the extract did not say.
nonisolated struct PlaceNotes: Codable, Sendable {
    var coordinates: [String: PlaceCoordinate] = [:]
    /// Place id → roaster seed slugs, or a roaster UUID when it is not in the
    /// seed. Non-empty means the person said so, and it replaces the extract.
    var learnedRoasters: [String: [String]] = [:]
    /// Cafés typed by hand when search had nothing to offer. They come back
    /// the next time a place is picked.
    var customPlaces: [Place] = []

    private enum CodingKeys: String, CodingKey {
        case coordinates, learnedRoasters, customPlaces
    }

    init(
        coordinates: [String: PlaceCoordinate] = [:],
        learnedRoasters: [String: [String]] = [:],
        customPlaces: [Place] = []
    ) {
        self.coordinates = coordinates
        self.learnedRoasters = learnedRoasters
        self.customPlaces = customPlaces
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        coordinates = try container.decodeIfPresent([String: PlaceCoordinate].self, forKey: .coordinates) ?? [:]
        learnedRoasters = try container.decodeIfPresent([String: [String]].self, forKey: .learnedRoasters) ?? [:]
        customPlaces = try container.decodeIfPresent([Place].self, forKey: .customPlaces) ?? []
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(coordinates, forKey: .coordinates)
        try container.encode(learnedRoasters, forKey: .learnedRoasters)
        try container.encode(customPlaces, forKey: .customPlaces)
    }
}

/// The bundled Paris cafés, plus the notes this device has added.
@Observable
final class PlaceIndex {
    let places: [SeedPlace]

    @ObservationIgnored private let byID: [String: SeedPlace]
    @ObservationIgnored private let notesStore: JSONDocumentStore<PlaceNotes>
    @ObservationIgnored private var notes: PlaceNotes
    @ObservationIgnored private var geocodeTask: Task<Void, Never>?

    init(
        places: [SeedPlace] = ReferenceBase.parisPlaces,
        notes: JSONDocumentStore<PlaceNotes> = JSONDocumentStore(filename: "place-notes.json")
    ) {
        self.places = places
        self.byID = Dictionary(places.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.notesStore = notes
        self.notes = notes.load() ?? PlaceNotes()
    }

    func place(id: String) -> SeedPlace? {
        byID[id]
    }

    /// Closed places stay out of the picker. Temporarily closed ones stay in,
    /// with their tag.
    var pickable: [SeedPlace] {
        places.filter { $0.status != .closed }
    }

    /// An old card's place name, including a café that has since closed.
    /// Ambiguous names match nothing.
    func match(name: String) -> SeedPlace? {
        let key = SeedPlace.fold(name)
        guard !key.isEmpty else { return nil }
        let hits = places.filter { SeedPlace.fold($0.name) == key }
        return hits.count == 1 ? hits[0] : nil
    }

    func coordinate(for id: String) -> PlaceCoordinate? {
        if let place = place(id: id),
           let latitude = place.latitude,
           let longitude = place.longitude {
            return PlaceCoordinate(latitude: latitude, longitude: longitude)
        }
        return notes.coordinates[id]
    }

    /// Roasters this place serves. A link the person confirmed replaces the
    /// extract; an empty learned list does not, so "we don't know" stays empty
    /// rather than pretending the extract was wrong.
    func servedRoasterIDs(for placeID: String) -> [String] {
        if let learned = notes.learnedRoasters[placeID], !learned.isEmpty {
            return learned
        }
        return place(id: placeID)?.roasterIDs ?? []
    }

    /// A name typed when Maps and the seed had no exact match. The same
    /// spelling is kept once.
    func addCustom(_ place: Place) {
        let key = SeedPlace.fold(place.name)
        guard !key.isEmpty else { return }
        guard !notes.customPlaces.contains(where: { SeedPlace.fold($0.name) == key }) else { return }
        notes.customPlaces.insert(place, at: 0)
        persist()
    }

    func custom(matching query: String) -> [Place] {
        let needle = SeedPlace.fold(query)
        guard !needle.isEmpty else { return notes.customPlaces }
        return notes.customPlaces.filter {
            SeedPlace.fold($0.name).contains(needle) || SeedPlace.fold($0.address).contains(needle)
        }
    }

    func remember(placeID: String, roasterID: String) {
        var current = notes.learnedRoasters[placeID] ?? []
        guard !current.contains(roasterID) else { return }
        current.append(roasterID)
        notes.learnedRoasters[placeID] = current
        persist()
    }

    func pickable(matching query: String) -> [SeedPlace] {
        let needle = SeedPlace.fold(query)
        guard !needle.isEmpty else { return pickable }
        return pickable.filter {
            SeedPlace.fold($0.name).contains(needle)
                || SeedPlace.fold($0.brand).contains(needle)
                || SeedPlace.fold($0.address).contains(needle)
        }
    }

    /// Closest places that already have a coordinate, within `meters`.
    func nearby(
        _ pool: [SeedPlace],
        from coordinate: CLLocationCoordinate2D,
        within meters: CLLocationDistance = 1_500
    ) -> [SeedPlace] {
        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return pool.compactMap { place -> (SeedPlace, CLLocationDistance)? in
            guard let stored = self.coordinate(for: place.id) else { return nil }
            let point = CLLocation(latitude: stored.latitude, longitude: stored.longitude)
            let distance = origin.distance(from: point)
            return distance <= meters ? (place, distance) : nil
        }
        .sorted { $0.1 < $1.1 }
        .map(\.0)
    }

    func byArrondissement(_ pool: [SeedPlace]) -> [(title: String, places: [SeedPlace])] {
        let groups = Dictionary(grouping: pool) { $0.arrondissement }
        return groups.keys.sorted { lhs, rhs in
            switch (lhs, rhs) {
            case let (left?, right?): return left < right
            case (nil, _?): return false
            case (_?, nil): return true
            case (nil, nil): return false
            }
        }
        .map { key in
            let title = key.map(SeedPlace.arrondissementTitle) ?? "Paris"
            let entries = (groups[key] ?? []).sorted {
                $0.name.localizedCompare($1.name) == .orderedAscending
            }
            return (title, entries)
        }
    }

    /// One lookup. Used when a place is chosen and when the background pass
    /// reaches it. A failure leaves the coordinate unset.
    func geocode(_ place: SeedPlace) async -> PlaceCoordinate? {
        if let cached = coordinate(for: place.id) { return cached }
        let query = [place.address, place.city, "France"]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        guard !query.isEmpty else { return nil }
        let marks = try? await CLGeocoder().geocodeAddressString(query)
        guard let location = marks?.first?.location?.coordinate else { return nil }
        let coordinate = PlaceCoordinate(latitude: location.latitude, longitude: location.longitude)
        notes.coordinates[place.id] = coordinate
        persist()
        return coordinate
    }

    /// Walks the open places that have no coordinate yet, about one a second.
    /// Called only once location has been granted, and never from the screen
    /// that is waiting on it.
    func beginGeocoding() {
        guard geocodeTask == nil else { return }
        let pending = pickable.map(\.id).filter { coordinate(for: $0) == nil }
        guard !pending.isEmpty else { return }
        geocodeTask = Task {
            for id in pending {
                if Task.isCancelled { break }
                if notes.coordinates[id] != nil { continue }
                if let place = place(id: id) {
                    _ = await geocode(place)
                }
                try? await Task.sleep(for: .seconds(1))
            }
            geocodeTask = nil
        }
    }

    private func persist() {
        try? notesStore.save(notes)
    }
}
