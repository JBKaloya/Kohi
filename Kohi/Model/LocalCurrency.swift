import CoreLocation
import Foundation
import Observation
import os

/// The currency a new price starts on: where you are, else the phone's
/// region, else euros. Always a proposal, never a lock: the currency chips
/// stay the one way to change it.
@MainActor
@Observable
final class LocalCurrency {
    static let shared = LocalCurrency()

    /// ISO 3166 code of the last place a fix was resolved to. Kept across
    /// launches, so a card scanned before the first fix still lands right.
    private(set) var countryCode: String?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var resolvedAround: CLLocation?
    @ObservationIgnored private let geocoder = CLGeocoder()

    private static let countryKey = "kohi.localCurrency.country"
    /// A country does not change between two screens; a new lookup only when
    /// the fix has moved this far.
    private static let refreshDistance: CLLocationDistance = 20_000

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        countryCode = defaults.string(forKey: Self.countryKey)
    }

    var proposed: String {
        Self.proposed(countryCode: countryCode, phoneCurrency: Locale.current.currency?.identifier)
    }

    /// Reverse-geocodes the fix to a country, once per area. Failures keep
    /// whatever was known, which the cascade then falls through.
    func learn(from coordinate: CLLocationCoordinate2D) async {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        if let resolvedAround, resolvedAround.distance(from: location) < Self.refreshDistance { return }
        resolvedAround = location
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            guard let code = placemarks.first?.isoCountryCode, Self.currency(forCountry: code) != nil else { return }
            countryCode = code
            defaults.set(code, forKey: Self.countryKey)
        } catch {
            resolvedAround = nil
            Log.app.notice("local currency: no country for the fix (\(error.localizedDescription))")
        }
    }

    /// ISO 4217 for an ISO 3166 country, nil for a code that is not a country.
    nonisolated static func currency(forCountry code: String) -> String? {
        let region = Locale.Region(code.uppercased())
        guard Locale.Region.isoRegions.contains(region) else { return nil }
        let locale = Locale(components: Locale.Components(languageCode: .english, languageRegion: region))
        guard let currency = locale.currency?.identifier, currency != "XXX" else { return nil }
        return currency
    }

    nonisolated static func proposed(countryCode: String?, phoneCurrency: String?) -> String {
        if let countryCode, let currency = currency(forCountry: countryCode) { return currency }
        if let phoneCurrency, !phoneCurrency.isEmpty { return phoneCurrency.uppercased() }
        return "EUR"
    }
}
