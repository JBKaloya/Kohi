import Foundation

/// Open, closed, or temporarily closed. Closed places stay in the seed so an
/// old card ("bought at Brouillon, May 2025") still resolves. They are not
/// offered in the picker.
nonisolated enum PlaceStatus: String, Codable, Hashable, Sendable {
    case open
    case closed
    case temp
}

/// A Paris café or roaster shop from `places-paris.json`.
///
/// Coordinates are embedded when the seed build had a confident geocode.
/// `PlaceIndex` fills the rest later and keeps that result on device.
nonisolated struct SeedPlace: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var brand: String
    var address: String
    var postalCode: String
    var arrondissement: Int?
    var city: String
    var roasterIDs: [String]
    var status: PlaceStatus
    var closedOn: String?
    var fetchedAt: String
    /// Filled by `Tools/SeedParis/geocode.py` and copied in by `build.py`.
    /// Nil when the address could not be placed. `PlaceIndex` geocodes those
    /// later and keeps the result on device.
    var latitude: Double?
    var longitude: Double?

    init(
        id: String,
        name: String,
        brand: String,
        address: String,
        postalCode: String,
        arrondissement: Int?,
        city: String,
        roasterIDs: [String],
        status: PlaceStatus,
        closedOn: String?,
        fetchedAt: String,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.brand = brand
        self.address = address
        self.postalCode = postalCode
        self.arrondissement = arrondissement
        self.city = city
        self.roasterIDs = roasterIDs
        self.status = status
        self.closedOn = closedOn
        self.fetchedAt = fetchedAt
        self.latitude = latitude
        self.longitude = longitude
    }

    /// "Closed · May 2026", "Temporarily closed", or nothing when the place
    /// is open. The editorial score never appears.
    var statusTag: String? {
        switch status {
        case .open:
            return nil
        case .temp:
            return Copy.temporarilyClosed
        case .closed:
            if let label = Self.monthLabel(closedOn) {
                return "Closed · \(label)"
            }
            return "Closed"
        }
    }

    /// Letters and digits only. Place names keep words like "coffee": folding
    /// those out, the way roaster names do, would make "The Coffee" match
    /// everything.
    static func fold(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }

    /// `2026-05` → "May 2026". Nil when the string is not a year-month.
    static func monthLabel(_ yearMonth: String?) -> String? {
        guard let yearMonth, yearMonth.count >= 7 else { return nil }
        let parts = yearMonth.split(separator: "-")
        guard parts.count >= 2, let month = Int(parts[1]), (1...12).contains(month) else { return nil }
        let names = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return "\(names[month - 1]) \(parts[0])"
    }

    static func arrondissementTitle(_ number: Int) -> String {
        let suffix: String
        switch number {
        case 1: suffix = "st"
        case 2: suffix = "nd"
        case 3: suffix = "rd"
        default: suffix = "th"
        }
        return "\(number)\(suffix)"
    }
}

/// What choosing a place does to an empty roaster field.
///
/// One served roaster is filled in. Several are offered, not picked: a wrong
/// link is worse than a chip the person can tap.
nonisolated enum PlaceRoasterFill {
    static func link(servedIDs: [String], roasterIsEmpty: Bool) -> String? {
        guard roasterIsEmpty, servedIDs.count == 1 else { return nil }
        return servedIDs[0]
    }
}
