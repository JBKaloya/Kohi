import CoreLocation
import Foundation

/// A coffee shop or roaster attached to a card, resolved through MapKit.
nonisolated struct Place: Codable, Hashable, Sendable {
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Single line for the detail view: "Kaffeine, 66 Great Titchfield St, London".
    var summary: String {
        address.isEmpty ? name : "\(name), \(address)"
    }
}
