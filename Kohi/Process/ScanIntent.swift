import Foundation

/// One location reading, with how sure it is and when it was taken.
nonisolated struct Fix: Equatable, Sendable {
    var latitude: Double
    var longitude: Double
    /// Metres, as Core Location reports it. Smaller is better.
    var accuracy: Double
    var at: Date

    func distance(toLatitude latitude: Double, longitude: Double) -> Double {
        let radius = 6_371_000.0
        let lat1 = self.latitude * .pi / 180
        let lat2 = latitude * .pi / 180
        let dLat = lat2 - lat1
        let dLon = (longitude - self.longitude) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * radius * atan2(sqrt(a), sqrt(1 - a))
    }
}

/// What the scanner is for: a bag for the collection, or a cup at a café.
nonisolated enum ScanPurpose: Equatable, Sendable {
    case bag
    case cup(PlaceSuggestion)
}

/// The answer given in the "What are you scanning?" sheet.
nonisolated enum ScanAnswer: Sendable {
    case cup
    case bag
}

/// A spot where the question was answered, rounded to roughly a hundred
/// metres. Two *A bag* answers in a row there and the question stops.
nonisolated struct ScanSpot: Codable, Equatable, Sendable {
    var latitude: Double
    var longitude: Double
    var bagStreak: Int
    var updatedAt: Date

    static let quietAfter = 2

    var isQuiet: Bool { bagStreak >= Self.quietAfter }

    static func rounded(_ value: Double) -> Double {
        (value * 1000).rounded() / 1000
    }

    func covers(_ fix: Fix) -> Bool {
        latitude == Self.rounded(fix.latitude) && longitude == Self.rounded(fix.longitude)
    }
}

/// The spots, kept on the phone only. Never synced: where you stand is yours.
nonisolated enum ScanSpots {
    static let key = "scan.spots"
    static let limit = 20

    static func load(from defaults: UserDefaults = .standard) -> [ScanSpot] {
        guard let data = defaults.data(forKey: key),
              let spots = try? JSONDecoder().decode([ScanSpot].self, from: data) else { return [] }
        return spots
    }

    static func save(_ spots: [ScanSpot], to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(spots) else { return }
        defaults.set(data, forKey: key)
    }

    static func clear(_ defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }

    static func record(_ answer: ScanAnswer, at fix: Fix, now: Date = .now, in defaults: UserDefaults = .standard) {
        save(recording(answer, at: fix, in: load(from: defaults), now: now), to: defaults)
    }

    /// *A cup* resets the spot. *A bag* adds one to its streak. The most
    /// recently answered spots are kept, up to `limit`.
    static func recording(_ answer: ScanAnswer, at fix: Fix, in spots: [ScanSpot], now: Date) -> [ScanSpot] {
        var spots = spots
        var spot = spots.first { $0.covers(fix) } ?? ScanSpot(
            latitude: ScanSpot.rounded(fix.latitude),
            longitude: ScanSpot.rounded(fix.longitude),
            bagStreak: 0,
            updatedAt: now
        )
        spots.removeAll { $0.covers(fix) }
        switch answer {
        case .cup: spot.bagStreak = 0
        case .bag: spot.bagStreak += 1
        }
        spot.updatedAt = now
        spots.insert(spot, at: 0)
        return Array(spots.sorted { $0.updatedAt > $1.updatedAt }.prefix(limit))
    }
}

/// Whether a scan from home should ask "A cup here, or a bag?".
///
/// It asks only when the signal is strong: a recent, precise fix, very close
/// to a café you have been to, a café the seed knows, or a café Maps knows.
/// Anything weaker and the scan goes straight to the bag flow, as before.
nonisolated enum ScanIntent: Equatable, Sendable {
    case bag
    case ask(PlaceSuggestion)

    static let maxAccuracy: Double = 65
    static let freshness: TimeInterval = 5 * 60
    static let yoursRadius: Double = 75
    static let seedRadius: Double = 75
    static let mapsRadius: Double = 40

    static func isUsable(_ fix: Fix?, now: Date) -> Bool {
        guard let fix else { return false }
        return fix.accuracy >= 0 && fix.accuracy <= maxAccuracy && now.timeIntervalSince(fix.at) <= freshness
    }

    static func decide(
        fix: Fix?,
        yours: [PlaceSuggestion],
        seeds: [PlaceSuggestion],
        maps: [Place],
        spots: [ScanSpot],
        now: Date = .now
    ) -> ScanIntent {
        guard let fix, isUsable(fix, now: now) else { return .bag }
        if spots.contains(where: { $0.covers(fix) && $0.isQuiet }) { return .bag }

        func nearest(_ candidates: [PlaceSuggestion], within radius: Double) -> PlaceSuggestion? {
            candidates
                .filter { $0.place.hasResolvedCoordinate }
                .map { ($0, fix.distance(toLatitude: $0.place.latitude, longitude: $0.place.longitude)) }
                .filter { $0.1 <= radius }
                .min { $0.1 < $1.1 }?
                .0
        }

        if let hit = nearest(yours, within: yoursRadius) { return .ask(hit) }
        if let hit = nearest(seeds, within: seedRadius) { return .ask(hit) }
        let cafes = maps.map { PlaceSuggestion(place: $0, placeID: nil, source: .maps) }
        if let hit = nearest(cafes, within: mapsRadius) { return .ask(hit) }
        return .bag
    }
}

/// Something that can take a fix. The home only asks one that is already
/// allowed to, so the grid never shows the location prompt.
protocol FixSource: AnyObject {
    var fix: Fix? { get }
    func start()
}

enum HomeFix {
    /// Starts a fix when location is already allowed and the last one is
    /// missing or stale. Returns whether it started one.
    @discardableResult
    static func refresh(_ source: some FixSource, isAuthorized: Bool, now: Date = .now) -> Bool {
        guard isAuthorized else { return false }
        if let fix = source.fix, now.timeIntervalSince(fix.at) <= ScanIntent.freshness { return false }
        source.start()
        return true
    }
}
