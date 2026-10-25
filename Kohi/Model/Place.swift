import CoreLocation
import Foundation

/// A coffee shop or roaster attached to a card, resolved through MapKit.
nonisolated struct Place: Codable, Hashable, Sendable {
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double
    /// `MKMapItem.Identifier`, when the place came from Maps. The stable way
    /// to tell two cafés with the same name apart.
    var mapItemID: String? = nil
    var city: String? = nil
    var country: String? = nil

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Single line for the detail view: "Kaffeine, 66 Great Titchfield St, London".
    var summary: String {
        address.isEmpty ? name : "\(name), \(address)"
    }

    /// A seed place that has not been geocoded yet is stored at 0, 0. That is
    /// not a pin, so maps should search the address instead.
    var hasResolvedCoordinate: Bool {
        latitude != 0 || longitude != 0
    }

    var mapQuery: String {
        let query = [name, address].filter { !$0.isEmpty }.joined(separator: ", ")
        return query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
    }

    var appleMapsURL: URL {
        if hasResolvedCoordinate {
            return URL(string: "maps://?q=\(mapQuery)&ll=\(latitude),\(longitude)")!
        }
        return URL(string: "maps://?q=\(mapQuery)")!
    }

    var googleMapsAppURL: URL {
        if hasResolvedCoordinate {
            return URL(string: "comgooglemaps://?q=\(mapQuery)&center=\(latitude),\(longitude)")!
        }
        return URL(string: "comgooglemaps://?q=\(mapQuery)")!
    }

    var googleMapsWebURL: URL {
        if hasResolvedCoordinate {
            return URL(string: "https://www.google.com/maps/search/?api=1&query=\(latitude),\(longitude)")!
        }
        return URL(string: "https://www.google.com/maps/search/?api=1&query=\(mapQuery)")!
    }
}
