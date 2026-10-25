import Foundation

/// ISO 3166-1 alpha-2 for a stored origin name. The archive keeps the English
/// whitelist from `FieldParser`, not a country code. Names that are not on
/// that list, or that name more than one country, produce no circle.
nonisolated enum OriginCode {
    static func alpha2(for country: String) -> String? {
        let key = country.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        return codes[key]
    }

    /// Every code the whitelist can produce, once each.
    static var allCodes: [String] { Array(Set(codes.values)).sorted() }

    /// Closed map, one entry per unambiguous name on the origin whitelist.
    /// Sumatra, Java and Sulawesi are Indonesian islands. Hawaii is the US.
    /// Congo and Timor are omitted: each name covers two countries.
    private static let codes: [String: String] = [
        "Ethiopia": "ET",
        "Kenya": "KE",
        "Rwanda": "RW",
        "Burundi": "BI",
        "Tanzania": "TZ",
        "Uganda": "UG",
        "Colombia": "CO",
        "Brazil": "BR",
        "Peru": "PE",
        "Bolivia": "BO",
        "Ecuador": "EC",
        "Guatemala": "GT",
        "Honduras": "HN",
        "El Salvador": "SV",
        "Nicaragua": "NI",
        "Costa Rica": "CR",
        "Panama": "PA",
        "Mexico": "MX",
        "Jamaica": "JM",
        "Indonesia": "ID",
        "Sumatra": "ID",
        "Java": "ID",
        "Sulawesi": "ID",
        "Papua New Guinea": "PG",
        "India": "IN",
        "Vietnam": "VN",
        "Thailand": "TH",
        "China": "CN",
        "Yemen": "YE",
        "Myanmar": "MM",
        "Laos": "LA",
        "Taiwan": "TW",
        "Philippines": "PH",
        "Malawi": "MW",
        "Zambia": "ZM",
        "Nepal": "NP",
        "Zimbabwe": "ZW",
        "Cameroon": "CM",
        "Madagascar": "MG",
        "Haiti": "HT",
        "Dominican Republic": "DO",
        "Cuba": "CU",
        "Venezuela": "VE",
        "Sri Lanka": "LK",
        "Hawaii": "US",
    ]
}
