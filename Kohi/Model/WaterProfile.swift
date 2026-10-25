import Foundation

nonisolated enum WaterSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case tap
    case filtered
    case bottled
    /// Distilled water plus a mineral product or a DIY concentrate.
    case recipe

    var id: String { rawValue }

    var label: String {
        switch self {
        case .tap: "Tap"
        case .filtered: "Filtered"
        case .bottled: "Bottled"
        case .recipe: "Recipe"
        }
    }
}

/// The water, which is 98 % of the cup.
///
/// TDS alone says almost nothing: the same 150 mg/L can be mostly bicarbonate
/// (flat, muted) or mostly magnesium (bright, sweet). So the four ions are
/// stored, and hardness and alkalinity are derived from them rather than typed.
nonisolated struct WaterProfile: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var source: WaterSource
    /// mg/L, as measured or printed on the label.
    var tds: Double?
    var calcium: Double?
    var magnesium: Double?
    var sodium: Double?
    var bicarbonate: Double?
    /// Mineral product, e.g. "Third Wave Water — Classic".
    var additiveName: String?
    /// Free text: "1 sachet / 1 L", "3 drops".
    var additiveDose: String?
    /// Typed mineral product from the reference base.
    var mineralProductID: String?
    var filtrationSystem: FiltrationSystem?
    var waterBase: WaterBase?
    var notes: String
    var isDefault: Bool
    /// Row id in the bundled reference base, when this came from a known water.
    var waterRef: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String = "",
        source: WaterSource = .tap,
        tds: Double? = nil,
        calcium: Double? = nil,
        magnesium: Double? = nil,
        sodium: Double? = nil,
        bicarbonate: Double? = nil,
        additiveName: String? = nil,
        additiveDose: String? = nil,
        mineralProductID: String? = nil,
        filtrationSystem: FiltrationSystem? = nil,
        waterBase: WaterBase? = nil,
        notes: String = "",
        isDefault: Bool = false,
        waterRef: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.source = source
        self.tds = tds
        self.calcium = calcium
        self.magnesium = magnesium
        self.sodium = sodium
        self.bicarbonate = bicarbonate
        self.additiveName = additiveName
        self.additiveDose = additiveDose
        self.mineralProductID = mineralProductID
        self.filtrationSystem = filtrationSystem
        self.waterBase = waterBase
        self.notes = notes
        self.isDefault = isDefault
        self.waterRef = waterRef
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: - Derived

    /// General hardness in ppm CaCO₃ ≈ 2.50 × Ca + 4.12 × Mg (annexe C1).
    /// Nil when neither ion is known — a hardness of zero would be a claim.
    var generalHardness: Double? {
        guard calcium != nil || magnesium != nil else { return nil }
        return 2.50 * (calcium ?? 0) + 4.12 * (magnesium ?? 0)
    }

    /// Alkalinity in ppm CaCO₃ ≈ 0.82 × HCO₃ (annexe C1).
    var alkalinity: Double? {
        guard let bicarbonate else { return nil }
        return 0.82 * bicarbonate
    }

    /// "150 mg/L · GH 68 · KH 40", dropping what is unknown.
    var summary: String {
        var parts: [String] = []
        if let tds { parts.append("\(GrindRange.number(tds)) ppm") }
        if let hardness = generalHardness { parts.append("GH \(GrindRange.number(hardness))") }
        if let alkalinity { parts.append("KH \(GrindRange.number(alkalinity))") }
        if let additiveName, !additiveName.isEmpty { parts.append(additiveName) }
        return parts.isEmpty ? source.label : parts.joined(separator: " · ")
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? source.label : trimmed
    }
}

nonisolated extension WaterProfile {
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        source = try c.decodeIfPresent(WaterSource.self, forKey: .source) ?? .tap
        tds = try c.decodeIfPresent(Double.self, forKey: .tds)
        calcium = try c.decodeIfPresent(Double.self, forKey: .calcium)
        magnesium = try c.decodeIfPresent(Double.self, forKey: .magnesium)
        sodium = try c.decodeIfPresent(Double.self, forKey: .sodium)
        bicarbonate = try c.decodeIfPresent(Double.self, forKey: .bicarbonate)
        additiveName = try c.decodeIfPresent(String.self, forKey: .additiveName)
        additiveDose = try c.decodeIfPresent(String.self, forKey: .additiveDose)
        mineralProductID = try c.decodeIfPresent(String.self, forKey: .mineralProductID)
        filtrationSystem = try c.decodeIfPresent(FiltrationSystem.self, forKey: .filtrationSystem)
        waterBase = try c.decodeIfPresent(WaterBase.self, forKey: .waterBase)
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        isDefault = try c.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        waterRef = try c.decodeIfPresent(String.self, forKey: .waterRef)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .now
    }
}

extension WaterProfile {
    /// Tap stays put. Bottled, recipe and filtered water are chosen per cup.
    var isFixedInstallation: Bool { source == .tap }
}

/// The SCA brewing-water targets (annexe C1, SCAA 2009). Shown as a hairline
/// band under a value, never as a verdict: water outside the band still makes
/// coffee, and the "filter light roast" trend deliberately sits below it on
/// alkalinity.
nonisolated enum WaterTarget {
    static let tds = (range: 75.0...250.0, target: 150.0, unit: "ppm")
    static let hardness = (range: 17.0...85.0, target: 68.0, unit: "ppm")
    static let alkalinity = (range: 30.0...50.0, target: 40.0, unit: "ppm")
}
