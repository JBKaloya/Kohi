import Foundation

/// Paper, cloth or metal geometry. What has to match the dripper.
nonisolated enum FilterShape: String, Codable, CaseIterable, Identifiable, Sendable {
    case cone60
    case coneDeep
    case wave
    case flatSmooth
    case chemex
    case melitta
    case disc
    case basket
    case cloth
    case dedicated
    case ufo

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cone60: "Cone 60°"
        case .coneDeep: "Deep cone"
        case .wave: "Wave"
        case .flatSmooth: "Flat"
        case .chemex: "Chemex"
        case .melitta: "Melitta"
        case .disc: "Disc"
        case .basket: "Basket"
        case .cloth: "Cloth"
        case .dedicated: "Dedicated"
        case .ufo: "UFO"
        }
    }

    var takesRinse: Bool {
        switch self {
        case .basket: false
        case .dedicated: true
        default: true
        }
    }

    /// Seed tokens, including `none` (no paper) and hyphenated CSV forms.
    static func parse(_ raw: String) -> FilterShape? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed == "none" { return nil }
        if let exact = FilterShape(rawValue: trimmed) { return exact }
        switch trimmed {
        case "cone-deep": return .coneDeep
        default: return nil
        }
    }

    static func parseList(_ raw: String?) -> [FilterShape] {
        guard let raw else { return [] }
        return raw.split(separator: ";").compactMap { parse(String($0)) }
    }

    static func parseList(_ values: [String]) -> [FilterShape] {
        values.compactMap(parse)
    }

    /// Shape (and size, when the column names one) from a dripper's `filter` field.
    /// Prefer `parseList` on the seed `shapes` column; this is the last resort
    /// for a free-text dripper typed in by hand.
    static func kit(from filter: String?, model: String) -> (size: String?, shapes: [FilterShape]) {
        let declared = (filter ?? "").lowercased()
        if declared.contains("métal") || declared.contains("metal") {
            return (nil, [])
        }
        let text = ((filter ?? "") + " " + model).lowercased()
        if text.contains("tissu") || text.contains("cloth") || text.contains("nel") {
            return (nil, [.cloth])
        }
        if text.contains("métal") || text.contains("metal") {
            return (nil, [])
        }
        if text.contains("chemex") {
            let size = cupsSize(in: model) ?? cupsSize(in: filter ?? "")
            return (size, [.chemex])
        }
        if text.contains("1x4") { return ("1x4", [.melitta]) }
        if text.contains("1x2") { return ("1x2", [.melitta]) }
        if text.contains("melitta") { return (nil, [.melitta]) }
        if text.contains("deep27") || text.contains("deep 27") { return ("27", [.coneDeep]) }
        if text.contains("wave 155") || text.contains("155") && text.contains("wave") {
            return ("155", [.wave])
        }
        if text.contains("wave 185") || text.contains("185") && text.contains("wave") {
            return ("185", [.wave])
        }
        if text.contains("b75") { return ("B75", [.wave]) }
        if text.contains("wave") { return (nil, [.wave]) }
        if text.contains("orea") { return (nil, [.wave, .flatSmooth]) }
        if text.contains("stagg") || text.contains("pulsar") || text.contains("tricolate")
            || text.contains("w40") || text.contains("w60") {
            return (nil, [.flatSmooth])
        }
        if text.contains("april") { return ("April", [.wave]) }
        if text.contains("basket") || text.contains("moccamaster") || text.contains("batch") {
            return (nil, [.basket])
        }
        if text.contains("aeropress") || text.contains("disc") || text.contains("siphon") {
            return ("60mm", [.disc])
        }
        if let size = v60Size(in: filter ?? "") ?? v60Size(in: model) {
            return (size, [.cone60])
        }
        if text.contains("v60") || text.contains("kono") || text.contains("origami")
            || text.contains("cafec") || text.contains("switch") || text.contains("cone")
            || text.contains("pegasus") {
            return (nil, [.cone60])
        }
        if (filter ?? "").localizedCaseInsensitiveContains("papier") {
            return (nil, [.cone60])
        }
        return (nil, [])
    }

    private static func v60Size(in text: String) -> String? {
        let lowered = text.lowercased()
        for size in ["03", "02", "01"] where lowered.contains(size) {
            return size
        }
        return nil
    }

    private static func cupsSize(in text: String) -> String? {
        let lowered = text.lowercased()
        for size in ["10 cups", "8 cups", "6 cups", "3 cups"] where lowered.contains(size) {
            return size.replacingOccurrences(of: " cups", with: "cup")
        }
        return nil
    }
}

nonisolated enum FilterMaterial: String, Codable, CaseIterable, Identifiable, Sendable {
    case paperWood
    case paperAbaca
    case paperBamboo
    case paperCellulose
    case paperMembrane
    case cloth
    case metal
    case synthetic

    var id: String { rawValue }

    var label: String {
        switch self {
        case .paperWood: "Wood paper"
        case .paperAbaca: "Abaca"
        case .paperBamboo: "Bamboo paper"
        case .paperCellulose: "Cellulose"
        case .paperMembrane: "Membrane"
        case .cloth: "Cloth"
        case .metal: "Metal"
        case .synthetic: "Synthetic"
        }
    }

    var isPaper: Bool {
        switch self {
        case .paperWood, .paperAbaca, .paperBamboo, .paperCellulose, .paperMembrane: true
        case .cloth, .metal, .synthetic: false
        }
    }
}

nonisolated enum Bleach: String, Codable, CaseIterable, Identifiable, Sendable {
    case bleachedTCF
    case unbleached
    case gentlyBleached

    var id: String { rawValue }

    var label: String {
        switch self {
        case .bleachedTCF: "Bleached"
        case .unbleached: "Unbleached"
        case .gentlyBleached: "Gently bleached"
        }
    }
}

nonisolated enum FlowClass: String, Codable, CaseIterable, Identifiable, Sendable {
    case veryFast
    case fast
    case standard
    case slow
    case verySlow
    case dependsOnDripper

    var id: String { rawValue }

    var label: String {
        switch self {
        case .veryFast: "very fast"
        case .fast: "fast"
        case .standard: "standard"
        case .slow: "slow"
        case .verySlow: "very slow"
        case .dependsOnDripper: "depends on dripper"
        }
    }

    /// Shown under the filter line: `fast ≈`.
    var tag: String {
        self == .dependsOnDripper ? "varies ≈" : "\(label) ≈"
    }

    var rank: Int {
        switch self {
        case .veryFast: 0
        case .fast: 1
        case .standard: 2
        case .slow: 3
        case .verySlow: 4
        case .dependsOnDripper: 2
        }
    }
}

/// A row in the bundled paper catalogue. `id` matches `filters-seed.csv`.
nonisolated struct FilterModel: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var brand: String
    var line: String
    var model: String
    var shape: FilterShape
    var sizes: [String]
    var fits: [String]
    var material: FilterMaterial?
    var bleach: Bleach?
    var thicknessUm: Double?
    var crepe: String?
    var density: String?
    var flowClass: FlowClass?
    var notes: String
    var source: String
    var status: String

    var displayName: String {
        let parts = [brand, line]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? model : parts.joined(separator: " ")
    }

    var shortName: String {
        let line = line.trimmingCharacters(in: .whitespaces)
        if line.isEmpty { return brand }
        return "\(brand) \(line)"
    }

    /// Name and shape only when the flow class is still to verify.
    var showsFlowClass: Bool {
        guard flowClass != nil else { return false }
        return !status.localizedCaseInsensitiveContains("à vérifier")
    }

    var isUnbleached: Bool { bleach == .unbleached }

    var takesRinse: Bool { shape.takesRinse }

    static func filters(matching brewers: [Equipment]) -> [FilterModel] {
        let shapes = Set(brewers.flatMap(\.resolvedFilterShapes))
        guard !shapes.isEmpty else { return ReferenceBase.filters }
        let matched = ReferenceBase.filters.filter { model in
            if shapes.contains(model.shape) { return true }
            return brewers.contains { FilterFit.named(model, fits: $0) }
        }
        if matched.isEmpty { return ReferenceBase.filters }
        return matched
    }

    static func filters(matching brewer: Equipment?) -> (items: [FilterModel], unmatched: Bool) {
        guard let brewer else { return (ReferenceBase.filters, false) }
        let shapes = Set(brewer.resolvedFilterShapes)
        if shapes.isEmpty {
            if brewer.family == .espresso {
                let discs = ReferenceBase.filters.filter { $0.shape == .disc }
                return discs.isEmpty ? (ReferenceBase.filters, true) : (discs, false)
            }
            return (ReferenceBase.filters, false)
        }
        let matched = ReferenceBase.filters.filter { model in
            if model.shape == .dedicated {
                return FilterFit.named(model, fits: brewer)
            }
            return shapes.contains(model.shape) || FilterFit.named(model, fits: brewer)
        }
        if matched.isEmpty { return (ReferenceBase.filters, true) }
        return (matched, false)
    }
}

/// Paper the user actually owns. Ids are stable so a brew that stored
/// `filterStockId` still resolves after a rename.
nonisolated struct FilterStock: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var modelId: String?
    var customName: String?
    var size: String
    var origin: String?
    /// Declared when this is a custom paper with no catalogue row.
    var shape: FilterShape?
    /// Brewer ids this paper is the default for.
    var isDefaultFor: [UUID]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        modelId: String? = nil,
        customName: String? = nil,
        size: String = "",
        origin: String? = nil,
        shape: FilterShape? = nil,
        isDefaultFor: [UUID] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.modelId = modelId
        self.customName = customName
        self.size = size
        self.origin = origin
        self.shape = shape
        self.isDefaultFor = isDefaultFor
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var model: FilterModel? {
        modelId.flatMap { id in ReferenceBase.filters.first { $0.id == id } }
    }

    var resolvedShape: FilterShape? { shape ?? model?.shape }

    var displayName: String {
        if let custom = customName?.trimmingCharacters(in: .whitespaces), !custom.isEmpty {
            return custom
        }
        if let model { return model.shortName }
        return size.isEmpty ? "Filter" : size
    }

    var isPaper: Bool {
        if let material = model?.material { return material.isPaper }
        if resolvedShape == .cloth { return false }
        if resolvedShape == .basket { return false }
        return true
    }

    /// `Cafec Abaca+ · 02 · fast ≈`, or name and shape when the class is unverified.
    var summary: String {
        var parts: [String] = []
        if let custom = customName?.trimmingCharacters(in: .whitespaces), !custom.isEmpty {
            parts.append(custom)
        } else if let model {
            parts.append(model.shortName)
        }
        if !size.isEmpty { parts.append(size) }
        if let flow = model?.flowClass, model?.showsFlowClass == true {
            parts.append(flow.tag)
        } else if let shape = resolvedShape {
            parts.append(shape.label)
        }
        return parts.joined(separator: " · ")
    }

    var searchText: String {
        [displayName, model?.brand, model?.line, model?.model, customName, size, origin]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
    }
}
