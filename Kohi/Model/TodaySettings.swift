import Foundation

/// The five numbers that change with this cup. A view of `Brew`, not a
/// nested stored struct — the archive stays flat.
nonisolated struct TodaySettings: Codable, Equatable, Sendable {
    var waterProfileId: UUID?
    var temperature: Double?
    var grind: GrindSetting
    var agitation: Agitation?
    var filterStockId: UUID?
}

nonisolated extension Brew {
    var today: TodaySettings {
        get {
            TodaySettings(
                waterProfileId: waterProfileID,
                temperature: temperature,
                grind: grind,
                agitation: agitation,
                filterStockId: filterStockId
            )
        }
        set {
            waterProfileID = newValue.waterProfileId
            temperature = newValue.temperature
            grind = newValue.grind
            agitation = newValue.agitation
            filterStockId = newValue.filterStockId
        }
    }
}
