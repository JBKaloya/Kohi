import CoreLocation
import Observation
import os

/// A single fix, used to bias place search toward where you are standing.
///
/// One shot rather than a live feed: the search only needs to know which city
/// you are in, and a card gets scanned once. Nothing here is stored on the card
/// — the coordinates that end up in `Place` come from Apple Maps, not from you.
@Observable
final class PlaceLocator: NSObject, CLLocationManagerDelegate, FixSource {
    private(set) var coordinate: CLLocationCoordinate2D?
    /// Metres. Only meaningful alongside `coordinate`.
    private(set) var horizontalAccuracy: CLLocationAccuracy?
    private(set) var fixedAt: Date?
    /// True once the request has been answered with a no. Search still works.
    private(set) var isDenied = false

    var fix: Fix? {
        guard let coordinate, let horizontalAccuracy, let fixedAt else { return nil }
        return Fix(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            accuracy: horizontalAccuracy,
            at: fixedAt
        )
    }

    @ObservationIgnored private let manager = CLLocationManager()

    convenience override init() {
        self.init(accuracy: kCLLocationAccuracyKilometer)
    }

    init(accuracy: CLLocationAccuracy) {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = accuracy
    }

    /// Whether a fix can be taken without asking. The tasting capture only
    /// locates on its own when this is already true.
    static var isAuthorized: Bool {
        #if DEBUG
        if DebugHooks.fakeFix != nil { return true }
        #endif
        return switch CLLocationManager().authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: true
        default: false
        }
    }

    /// Asks the first time, then simply reuses the answer.
    func start() {
        #if DEBUG
        if let fake = DebugHooks.fakeFix {
            coordinate = CLLocationCoordinate2D(latitude: fake.latitude, longitude: fake.longitude)
            horizontalAccuracy = fake.accuracy
            fixedAt = .now
            return
        }
        #endif
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            isDenied = true
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Only the status crosses over. The manager itself is not `Sendable`,
        // and the one this object owns is the same one anyway.
        let status = manager.authorizationStatus
        Task { @MainActor in apply(status) }
    }

    private func apply(_ status: CLAuthorizationStatus) {
        switch status {
        case .notDetermined:
            break
        case .authorizedWhenInUse, .authorizedAlways:
            isDenied = false
            manager.requestLocation()
        default:
            isDenied = true
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last else { return }
        let fix = location.coordinate
        let accuracy = location.horizontalAccuracy
        let at = location.timestamp
        Task { @MainActor in
            coordinate = fix
            horizontalAccuracy = accuracy
            fixedAt = at
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager, didFailWithError error: any Error
    ) {
        // Indoors, offline, airplane mode. The search falls back to unbiased,
        // which is what it did before there was a locator at all.
        Log.app.notice("place search: no fix, searching unbiased (\(error.localizedDescription))")
    }
}
