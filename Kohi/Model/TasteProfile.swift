import Foundation

/// Seven axes, 0 to 10. What the coffee was like, as opposed to what to change.
///
/// Separate from the three −/·/+ diagnostic axes on `Brew`. Absent means
/// not scored; `0` is a score ("no bitterness").
nonisolated struct TasteProfile: Codable, Hashable, Sendable {
    var values: [TasteAxis: Int]
    /// The 1…5 numbers this was migrated from, when decode lifted a legacy object.
    var legacy: [String: Int]?

    init(values: [TasteAxis: Int] = [:], legacy: [String: Int]? = nil) {
        self.values = values.reduce(into: [:]) { result, pair in
            guard (0...10).contains(pair.value) else { return }
            result[pair.key] = pair.value
        }
        self.legacy = legacy
    }

    init(
        acidity: Int? = nil,
        bitterness: Int? = nil,
        sweetness: Int? = nil,
        aroma: Int? = nil,
        aftertaste: Int? = nil,
        body: Int? = nil,
        clarity: Int? = nil
    ) {
        var values: [TasteAxis: Int] = [:]
        values[.acidity] = acidity
        values[.bitterness] = bitterness
        values[.sweetness] = sweetness
        values[.aroma] = aroma
        values[.aftertaste] = aftertaste
        values[.body] = body
        values[.clarity] = clarity
        self.init(values: values)
    }

    subscript(axis: TasteAxis) -> Int? {
        get { values[axis] }
        set {
            if let newValue, (0...10).contains(newValue) {
                values[axis] = newValue
            } else {
                values.removeValue(forKey: axis)
            }
        }
    }

    var isEmpty: Bool { values.isEmpty }

    var scoredAxes: [TasteAxis] {
        TasteAxis.allCases.filter { values[$0] != nil }
    }

    /// Spoken / comparable summary, omitting unscored axes.
    var accessibilityLabel: String {
        scoredAxes
            .compactMap { axis in
                guard let value = values[axis] else { return nil }
                return "\(axis.label) \(value)"
            }
            .joined(separator: ", ")
    }

    /// Diagnostic thresholds live on 0…10. A "low" score is ≤ 4; the
    /// midpoint used when an axis was not filled in is 5.
    static let lowThreshold = 4
    static let midDefault = 5

    /// Lift a 1…5 legacy score onto 0…10 without inventing a seventh axis.
    static func migrated(from legacy: [String: Int]) -> TasteProfile {
        var values: [TasteAxis: Int] = [:]
        for axis in TasteAxis.allCases where axis != .clarity {
            if let old = legacy[axis.rawValue], (1...5).contains(old) {
                values[axis] = old * 2
            }
        }
        return TasteProfile(values: values, legacy: legacy)
    }
}

nonisolated enum TasteAxis: String, Codable, CaseIterable, Identifiable, Sendable {
    case acidity
    case bitterness
    case sweetness
    case aroma
    case aftertaste
    case body
    case clarity

    var id: String { rawValue }

    var label: String {
        switch self {
        case .acidity: "Acidity"
        case .bitterness: "Bitterness"
        case .sweetness: "Sweetness"
        case .aroma: "Aroma"
        case .aftertaste: "Aftertaste"
        case .body: "Body"
        case .clarity: "Clarity"
        }
    }
}

nonisolated extension TasteProfile {
    enum CodingKeys: String, CodingKey {
        case values
        case aroma, acidity, sweetness, body, bitterness, aftertaste, clarity
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        var nested = c.nestedContainer(keyedBy: AxisKey.self, forKey: .values)
        for axis in TasteAxis.allCases {
            if let value = values[axis] {
                try nested.encode(value, forKey: AxisKey(axis))
            }
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let nested = try? c.nestedContainer(keyedBy: AxisKey.self, forKey: .values) {
            var values: [TasteAxis: Int] = [:]
            for axis in TasteAxis.allCases {
                if let value = try nested.decodeIfPresent(Int.self, forKey: AxisKey(axis)),
                   (0...10).contains(value)
                {
                    values[axis] = value
                }
            }
            self.values = values
            self.legacy = nil
            return
        }
        var legacy: [String: Int] = [:]
        for key in [CodingKeys.aroma, .acidity, .sweetness, .body, .bitterness, .aftertaste] {
            if let value = try c.decodeIfPresent(Int.self, forKey: key) {
                legacy[key.rawValue] = value
            }
        }
        if legacy.isEmpty {
            var values: [TasteAxis: Int] = [:]
            for axis in TasteAxis.allCases {
                if let key = CodingKeys(rawValue: axis.rawValue),
                   let value = try c.decodeIfPresent(Int.self, forKey: key),
                   (0...10).contains(value)
                {
                    values[axis] = value
                }
            }
            self.values = values
            self.legacy = nil
            return
        }
        self = TasteProfile.migrated(from: legacy)
    }

    struct AxisKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
        init(_ axis: TasteAxis) { stringValue = axis.rawValue }
    }
}
