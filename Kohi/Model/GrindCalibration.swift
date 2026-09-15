import Foundation

/// "My 22 clicks is your 700 µm" — one observed pair, from you.
///
/// This is the honest version of grind conversion. Maker step sizes describe
/// how far a burr travels, published ranges describe what people tend to do;
/// a calibration describes what actually worked on your grinder, for one
/// method. When one exists, the conversion uses it and stops apologising.
nonisolated struct GrindCalibration: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var grinderID: UUID
    var method: BrewMethod
    /// The setting in the grinder's own units: 22 clicks, 4.5 on the dial.
    var setting: Double
    /// The particle size you believe that setting produces, if you have any
    /// basis for a number — a sieve, a published measurement, a shop's readout.
    var micronsProxy: Double?
    var note: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        grinderID: UUID,
        method: BrewMethod,
        setting: Double,
        micronsProxy: Double? = nil,
        note: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.grinderID = grinderID
        self.method = method
        self.setting = setting
        self.micronsProxy = micronsProxy
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// "22 clicks ≈ 700 µm", or just the setting when you gave no number.
    var summary: String {
        let settingText = GrindRange.number(setting)
        guard let micronsProxy else { return settingText }
        return "\(settingText) ≈ \(GrindRange.number(micronsProxy)) µm"
    }
}

nonisolated extension GrindCalibration {
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        grinderID = try c.decodeIfPresent(UUID.self, forKey: .grinderID) ?? UUID()
        method = try c.decodeIfPresent(BrewMethod.self, forKey: .method) ?? .v60
        setting = try c.decodeIfPresent(Double.self, forKey: .setting) ?? 0
        micronsProxy = try c.decodeIfPresent(Double.self, forKey: .micronsProxy)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .now
    }
}
