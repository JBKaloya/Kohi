import CryptoKit
import Foundation

/// One row of `roasters-seed.json`: the Paris extract plus the Annexe D
/// roasters it did not already cover. Display data lives on `Roaster`; this
/// stays the bundled record (shops served, aliases, provenance).
nonisolated struct RoasterSeed: Codable, Identifiable, Hashable, Sendable {
    var slug: String
    var name: String
    var country: String
    var city: String
    var website: String?
    var instagram: String?
    /// How many Paris cafés serve this roaster, according to the extract.
    /// Sort key only. Never shown.
    var parisShopsServed: Int
    var ownShopIDs: [String]
    var aliases: [String]
    /// `specialtyCoffeeParis`, `annexeD`, or both.
    var sources: [String]
    var status: String
    var note: String
    var fetchedAt: String

    var id: String { slug }

    var websiteDomain: String? {
        Roaster.domain(of: website)
    }

    /// RFC 4122 UUID version 5, so every device files the same slug under the
    /// same id and a later push does not fork the shared index.
    static func stableUUID(slug: String) -> UUID {
        let namespace = UUID(uuidString: "C0FFEE00-0000-4000-8000-00000000A11E")!
        var data = Data()
        withUnsafeBytes(of: namespace.uuid) { data.append(contentsOf: $0) }
        data.append(contentsOf: Data("roaster:\(slug)".utf8))
        var bytes = Array(Insecure.SHA1.hash(data: data).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    /// `2026-10-01` becomes a stable timestamp. Re-applying the same extract
    /// must not look like an edit.
    static func stamped(_ fetchedAt: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: fetchedAt) ?? Date(timeIntervalSince1970: 0)
    }
}

/// Which extract has already been merged into `roasters.json`.
nonisolated struct RoasterSeedStamp: Codable, Sendable {
    var fetchedAt: String
}
