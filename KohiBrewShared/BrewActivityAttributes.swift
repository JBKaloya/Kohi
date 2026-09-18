import ActivityKit
import Foundation

/// Shared by the app and the brew widget. Compiled into both targets.
nonisolated struct BrewActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable, Sendable {
        var stepLabel: String
        var nowMass: Double?
        var targetMass: Double?
        var finalMass: Double
        var stepMasses: [Double]
        var stepIndex: Int
        var stepCount: Int
        var startedAt: Date
    }

    var coffeeName: String
    var methodLabel: String
}
