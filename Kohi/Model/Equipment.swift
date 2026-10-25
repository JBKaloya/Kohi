import Foundation

nonisolated enum EquipmentKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case grinder
    case brewer
    case espressoMachine
    case kettle
    case scale
    case accessory

    var id: String { rawValue }

    var label: String {
        switch self {
        case .grinder: "Grinder"
        case .brewer: "Brewer"
        case .espressoMachine: "Espresso machine"
        case .kettle: "Kettle"
        case .scale: "Scale"
        case .accessory: "Accessory"
        }
    }

    /// Plural heading for the Setup sections.
    var plural: String {
        switch self {
        case .grinder: "Grinders"
        case .brewer: "Brewers"
        case .espressoMachine: "Espresso machines"
        case .kettle: "Kettles"
        case .scale: "Scales"
        case .accessory: "Accessories"
        }
    }
}

nonisolated enum BurrType: String, Codable, CaseIterable, Identifiable, Sendable {
    case conical
    case flat

    var id: String { rawValue }
    var label: String { self == .conical ? "Conical" : "Flat" }
}

/// How the grind is set, which decides whether a converted setting can be a
/// decimal or has to land on a notch.
nonisolated enum GrindAdjustment: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Detented: 22 clicks, never 22.4.
    case clicks
    /// Continuous: any value in between is reachable.
    case stepless
    /// A numbered dial, read off a scale — continuous in practice.
    case dial

    var id: String { rawValue }

    var label: String {
        switch self {
        case .clicks: "Clicks"
        case .stepless: "Stepless"
        case .dial: "Dial"
        }
    }

    /// Whether a converted setting has to be rounded to a whole notch.
    var isDetented: Bool { self == .clicks }

    /// The word shown next to a grind value: clicks, number, or position.
    var unitLabel: String {
        switch self {
        case .clicks: "clicks"
        case .dial: "number"
        case .stepless: "position"
        }
    }
}

/// The settings that work for one method on one grinder — "espresso 8–12".
///
/// Declared by the user, or pre-filled from the reference base when it has a
/// verified hint. This is what makes a grind conversion possible at all: two
/// grinders can only be mapped onto each other through the range each covers.
nonisolated struct GrindRange: Codable, Hashable, Sendable, Identifiable {
    var method: BrewMethod
    var low: Double
    var high: Double

    var id: String { method.rawValue }

    init(method: BrewMethod, low: Double, high: Double) {
        self.method = method
        // Stored ordered so every consumer can assume low <= high.
        self.low = min(low, high)
        self.high = max(low, high)
    }

    var span: Double { high - low }

    /// "8–12", or "10" when the range is a single setting.
    var label: String {
        low == high ? Self.number(low) : "\(Self.number(low))–\(Self.number(high))"
    }

    static func number(_ value: Double) -> String {
        value == value.rounded()
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
    }
}

/// One thing in the cupboard.
///
/// Per-kind fields sit side by side as optionals rather than in a variant type:
/// the form shows the handful that apply, decoding tolerates all of them being
/// absent, and a kind gaining a field costs one property.
nonisolated struct Equipment: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var kind: EquipmentKind
    var brand: String
    var model: String
    var notes: String
    /// Methods this item is the default for. What pre-fills the brew sheet.
    var isDefaultFor: [BrewMethod]

    // Grinder
    /// Row id in the bundled reference base, or nil for a custom grinder.
    var grinderRef: String?
    /// Row id in `brewers.json`, when this brewer came from the dripper seed.
    var brewerRef: String?
    var burrType: BurrType?
    var burrMm: Double?
    var adjustment: GrindAdjustment?
    var stepsPerRotation: Int?
    /// Vertical burr travel per step, as published by the maker. A mechanical
    /// displacement, **not** a particle size: good for proportionality inside
    /// one grinder, useless for comparing two.
    var makerMicronsPerStep: Double?
    var ranges: [GrindRange]

    // Brewer
    var brewerType: String?
    var filterBrand: String?
    var filterShape: String?
    var filters: [BrewFilter]
    var defaultFilterId: UUID?
    /// Size the dripper takes (`02`, `185`, `6 cups`), when the seed names one.
    var size: String?
    var acceptsFilterShapes: [FilterShape]

    // Espresso machine
    var basketG: Double?
    var pressureBar: Double?

    // Kettle
    var isGooseneck: Bool?
    var hasTemperatureControl: Bool?

    // Scale
    var resolutionG: Double?
    var hasTimer: Bool?

    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        kind: EquipmentKind = .grinder,
        brand: String = "",
        model: String = "",
        notes: String = "",
        isDefaultFor: [BrewMethod] = [],
        grinderRef: String? = nil,
        brewerRef: String? = nil,
        burrType: BurrType? = nil,
        burrMm: Double? = nil,
        adjustment: GrindAdjustment? = nil,
        stepsPerRotation: Int? = nil,
        makerMicronsPerStep: Double? = nil,
        ranges: [GrindRange] = [],
        brewerType: String? = nil,
        filterBrand: String? = nil,
        filterShape: String? = nil,
        filters: [BrewFilter] = [],
        defaultFilterId: UUID? = nil,
        size: String? = nil,
        acceptsFilterShapes: [FilterShape] = [],
        basketG: Double? = nil,
        pressureBar: Double? = nil,
        isGooseneck: Bool? = nil,
        hasTemperatureControl: Bool? = nil,
        resolutionG: Double? = nil,
        hasTimer: Bool? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.kind = kind
        self.brand = brand
        self.model = model
        self.notes = notes
        self.isDefaultFor = isDefaultFor
        self.grinderRef = grinderRef
        self.brewerRef = brewerRef
        self.burrType = burrType
        self.burrMm = burrMm
        self.adjustment = adjustment
        self.stepsPerRotation = stepsPerRotation
        self.makerMicronsPerStep = makerMicronsPerStep
        self.ranges = ranges
        self.brewerType = brewerType
        self.filterBrand = filterBrand
        self.filterShape = filterShape
        self.filters = filters
        self.defaultFilterId = defaultFilterId
        self.size = size
        self.acceptsFilterShapes = acceptsFilterShapes
        self.basketG = basketG
        self.pressureBar = pressureBar
        self.isGooseneck = isGooseneck
        self.hasTemperatureControl = hasTemperatureControl
        self.resolutionG = resolutionG
        self.hasTimer = hasTimer
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// "Comandante C40 MK4", falling back to whichever half is filled.
    var displayName: String {
        let parts = [brand, model]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? kind.label : parts.joined(separator: " ")
    }

    func range(for method: BrewMethod) -> GrindRange? {
        ranges.first { $0.method == method }
    }

    var unitLabel: String {
        adjustment?.unitLabel ?? ""
    }

    /// The one-line summary shown in the `tag` column of a Setup row.
    var summary: String {
        var parts: [String] = []
        switch kind {
        case .grinder:
            if let burrType { parts.append(burrType.label) }
            if let burrMm { parts.append("\(GrindRange.number(burrMm)) mm") }
            if let adjustment { parts.append(adjustment.label.lowercased()) }
        case .brewer:
            if let brewerType, !brewerType.isEmpty { parts.append(brewerType) }
            if let first = filters.first, !first.displayName.isEmpty {
                parts.append(first.displayName)
            } else if let filterBrand, !filterBrand.isEmpty {
                parts.append(filterBrand)
            }
        case .espressoMachine:
            if let basketG { parts.append("\(GrindRange.number(basketG)) g basket") }
            if let pressureBar { parts.append("\(GrindRange.number(pressureBar)) bar") }
        case .kettle:
            if isGooseneck == true { parts.append("gooseneck") }
            if hasTemperatureControl == true { parts.append("temp control") }
        case .scale:
            if let resolutionG { parts.append("\(GrindRange.number(resolutionG)) g") }
            if hasTimer == true { parts.append("timer") }
        case .accessory:
            break
        }
        return parts.joined(separator: " · ")
    }
}

nonisolated extension Equipment {
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try c.decodeIfPresent(EquipmentKind.self, forKey: .kind) ?? .accessory
        brand = try c.decodeIfPresent(String.self, forKey: .brand) ?? ""
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? ""
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        isDefaultFor = try c.decodeIfPresent([BrewMethod].self, forKey: .isDefaultFor) ?? []
        grinderRef = try c.decodeIfPresent(String.self, forKey: .grinderRef)
        brewerRef = try c.decodeIfPresent(String.self, forKey: .brewerRef)
        burrType = try c.decodeIfPresent(BurrType.self, forKey: .burrType)
        burrMm = try c.decodeIfPresent(Double.self, forKey: .burrMm)
        adjustment = try c.decodeIfPresent(GrindAdjustment.self, forKey: .adjustment)
        stepsPerRotation = try c.decodeIfPresent(Int.self, forKey: .stepsPerRotation)
        makerMicronsPerStep = try c.decodeIfPresent(Double.self, forKey: .makerMicronsPerStep)
        ranges = try c.decodeIfPresent([GrindRange].self, forKey: .ranges) ?? []
        brewerType = try c.decodeIfPresent(String.self, forKey: .brewerType)
        filterBrand = try c.decodeIfPresent(String.self, forKey: .filterBrand)
        filterShape = try c.decodeIfPresent(String.self, forKey: .filterShape)
        // Only lift brand/shape when the new key is absent. An encoded empty
        // list is a choice; inventing a filter with a new id on every load
        // would churn the archive.
        if let stored = try c.decodeIfPresent([BrewFilter].self, forKey: .filters) {
            filters = stored
        } else {
            let brand = filterBrand?.trimmingCharacters(in: .whitespaces) ?? ""
            let shape = filterShape?.trimmingCharacters(in: .whitespaces) ?? ""
            filters = (!brand.isEmpty || !shape.isEmpty)
                ? [BrewFilter(brand: brand, shape: shape)]
                : []
        }
        defaultFilterId = try c.decodeIfPresent(UUID.self, forKey: .defaultFilterId)
            ?? filters.first?.id
        size = try c.decodeIfPresent(String.self, forKey: .size)
        acceptsFilterShapes = try c.decodeIfPresent([FilterShape].self, forKey: .acceptsFilterShapes) ?? []
        basketG = try c.decodeIfPresent(Double.self, forKey: .basketG)
        pressureBar = try c.decodeIfPresent(Double.self, forKey: .pressureBar)
        isGooseneck = try c.decodeIfPresent(Bool.self, forKey: .isGooseneck)
        hasTemperatureControl = try c.decodeIfPresent(Bool.self, forKey: .hasTemperatureControl)
        resolutionG = try c.decodeIfPresent(Double.self, forKey: .resolutionG)
        hasTimer = try c.decodeIfPresent(Bool.self, forKey: .hasTimer)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .now
    }
}
