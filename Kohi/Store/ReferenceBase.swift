import CryptoKit
import Foundation
import os

/// The bundled reference bases: grinders, bottled waters, mineral products.
///
/// Read-only, shipped with the app, and deliberately short. The PRD's gate is
/// that nothing marked "à vérifier" gets seeded, which is why the grinder list
/// carries maker step sizes but almost no usable ranges: those are practice
/// hints nobody has verified. Declaring your own range in Setup is what fills
/// that in, and the conversion says out loud which of the two it used.
nonisolated enum ReferenceBase {
    struct Grinder: Codable, Identifiable, Hashable, Sendable {
        let id: String
        var brand: String
        var model: String
        var isManual: Bool?
        var burrType: BurrType?
        var burrMm: Double?
        var adjustment: GrindAdjustment?
        var stepsPerRotation: Int?
        /// Maker-published burr travel per step. See the warning in annexe B:
        /// this is displacement, not particle size.
        var makerMicronsPerStep: Double?
        /// Indicative ranges per method. Empty unless verified.
        var ranges: [GrindRange]?
        var source: String?

        var displayName: String { "\(brand) \(model)" }
    }

    struct Water: Codable, Identifiable, Hashable, Sendable {
        let id: String
        var name: String
        var country: String?
        var calcium: Double?
        var magnesium: Double?
        var sodium: Double?
        var bicarbonate: Double?
        var tds: Double?
        var note: String?
        var source: String?
    }

    struct Knowledge: Codable, Identifiable, Hashable, Sendable {
        let id: String
        var topic: String
        var title: String
        var body: String
        var source: String
        var sourceURL: String?
        var year: Int?
        var type: String?
        var usage: String?

        enum CodingKeys: String, CodingKey {
            case id, topic, title, body, source, year, type, usage
            case sourceURL = "source_url"
        }
    }

    struct MineralProduct: Codable, Identifiable, Hashable, Sendable {
        let id: String
        var name: String
        var form: String?
        var composition: String?
        var tds: Double?
        var alkalinity: Double?
        var calcium: Double?
        var magnesium: Double?
        var sodium: Double?
        var bicarbonate: Double?
        var dose: String?
        var source: String?
        var verified: Bool?

        var compositionOnFile: Bool { verified == true }
    }

    /// A piece of kit in the bundled catalogue: brewers, kettles, scales,
    /// espresso machines. Grinders stay in `grinders.json` — they carry burr
    /// data this shape does not need.
    struct Item: Codable, Identifiable, Hashable, Sendable {
        struct Filter: Codable, Hashable, Sendable {
            var brand: String
            var shape: String
        }

        let id: String
        var kind: EquipmentKind
        var brand: String
        var model: String
        var variant: String?
        var family: BrewerType?
        var filters: [Filter]?
        var isGooseneck: Bool?
        var hasTemperatureControl: Bool?
        var resolutionG: Double?
        var hasTimer: Bool?
        var basketG: Double?
        var pressureBar: Double?
        var source: String

        var displayName: String {
            let variant = variant?.trimmingCharacters(in: .whitespaces) ?? ""
            let model = model.trimmingCharacters(in: .whitespaces)
            let named = variant.isEmpty ? model : "\(model) \(variant)"
            return [brand, named]
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }

        init(
            id: String,
            kind: EquipmentKind,
            brand: String,
            model: String,
            variant: String? = nil,
            family: BrewerType? = nil,
            filters: [Filter]? = nil,
            isGooseneck: Bool? = nil,
            hasTemperatureControl: Bool? = nil,
            resolutionG: Double? = nil,
            hasTimer: Bool? = nil,
            basketG: Double? = nil,
            pressureBar: Double? = nil,
            source: String
        ) {
            self.id = id
            self.kind = kind
            self.brand = brand
            self.model = model
            self.variant = variant
            self.family = family
            self.filters = filters
            self.isGooseneck = isGooseneck
            self.hasTemperatureControl = hasTemperatureControl
            self.resolutionG = resolutionG
            self.hasTimer = hasTimer
            self.basketG = basketG
            self.pressureBar = pressureBar
            self.source = source
        }

        init(_ grinder: Grinder) {
            self.init(
                id: grinder.id,
                kind: .grinder,
                brand: grinder.brand,
                model: grinder.model,
                source: grinder.source ?? ""
            )
        }

        init(_ brewer: Brewer) {
            self.init(
                id: brewer.id,
                kind: .brewer,
                brand: brewer.brand,
                model: brewer.model,
                family: brewer.dripperFamily.brewerType,
                filters: brewer.filter.map { [Filter(brand: brewer.brand, shape: $0)] },
                source: brewer.source ?? ""
            )
        }
    }

    struct Brewer: Codable, Identifiable, Hashable, Sendable {
        let id: String
        var brand: String
        var model: String
        var name: String?
        var family: String
        var bypass: String
        var filter: String?
        var shapes: [String]?
        var note: String?
        var source: String?
        var status: String?

        var displayName: String { name?.isEmpty == false ? name! : "\(brand) \(model)" }

        var dripperFamily: DripperFamily {
            DripperFamily(rawValue: family) ?? .other
        }

        var bypassLevel: BypassLevel? {
            BypassLevel(rawValue: bypass)
        }

        var filterShapes: [FilterShape] {
            if let shapes {
                return FilterShape.parseList(shapes)
            }
            return FilterShape.kit(from: filter, model: model).shapes
        }

        var declaresNoPaper: Bool {
            if let shapes, shapes.isEmpty { return true }
            return false
        }
    }

    static let grinders: [Grinder] = load("grinders")
    static let waters: [Water] = load("waters")
    static let mineralProducts: [MineralProduct] = load("mineral-products")
    static let kit: [Item] = load("equipment")
    static let brewers: [Brewer] = load("brewers")
    static let filters: [FilterModel] = load("filters")
    static let roasterSeeds: [RoasterSeed] = load("roasters-seed")
    static let parisPlaces: [SeedPlace] = load("places-paris")

    /// The reference recipes (annexe A), minus the rows the verification gate
    /// rejects. Each keeps its attribution, its source URL and how much of it
    /// was actually checked, because a recipe with no author is a rumour.
    static let recipes: [Recipe] = load("recipes").map(normalize)
    static let knowledge: [Knowledge] = load("knowledge")

    static func recipe(referenceID: String) -> Recipe? {
        recipes.first { $0.referenceID == referenceID }
    }

    static func recipes(for method: BrewMethod) -> [Recipe] {
        recipes.filter { $0.method == method }
    }

    /// Bundled recipes have no UUID in the file — an id minted at load time
    /// would change on every launch and break every reference to it. The id is
    /// derived from the row key instead, so it is the same on every device.
    private static func normalize(_ recipe: Recipe) -> Recipe {
        var normalized = recipe
        normalized.source = .reference
        guard let key = recipe.referenceID else { return normalized }
        return Recipe(
            id: stableID(key),
            name: normalized.name,
            method: normalized.method,
            dose: normalized.dose,
            water: normalized.water,
            beverage: normalized.beverage,
            temperature: normalized.temperature,
            temperatureMax: normalized.temperatureMax,
            seconds: normalized.seconds,
            grindLabel: normalized.grindLabel,
            grindMicronsLow: normalized.grindMicronsLow,
            grindMicronsHigh: normalized.grindMicronsHigh,
            steps: normalized.steps,
            source: .reference,
            evidence: normalized.evidence,
            attribution: normalized.attribution,
            sourceURL: normalized.sourceURL,
            notes: normalized.notes,
            referenceID: key,
            profileTags: normalized.profileTags,
            authorGrinder: normalized.authorGrinder,
            autoAdvance: true
        )
    }

    /// A UUID derived from a string, the way a version-5 UUID is: same input,
    /// same id, forever.
    static func stableID(_ key: String) -> UUID {
        var digest = Array(Insecure.MD5.hash(data: Data(key.utf8)))
        digest[6] = (digest[6] & 0x0F) | 0x30
        digest[8] = (digest[8] & 0x3F) | 0x80
        return UUID(uuid: (
            digest[0], digest[1], digest[2], digest[3],
            digest[4], digest[5], digest[6], digest[7],
            digest[8], digest[9], digest[10], digest[11],
            digest[12], digest[13], digest[14], digest[15]
        ))
    }

    static func grinder(id: String) -> Grinder? {
        grinders.first { $0.id == id }
    }

    static func brewer(id: String) -> Brewer? {
        brewers.first { $0.id == id }
    }

    static func water(id: String) -> Water? {
        waters.first { $0.id == id }
    }

    /// Reference grinders whose brand or model matches, for the picker.
    static func grinders(matching query: String) -> [Grinder] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return grinders }
        return grinders.filter {
            $0.displayName.localizedCaseInsensitiveContains(trimmed)
        }
    }

    /// Reference kit whose brand, model or variant matches, for the picker.
    /// Grinders come from `grinders.json`; everything else from `equipment.json`.
    static func equipment(kind: EquipmentKind, matching query: String) -> [Item] {
        let pool: [Item]
        switch kind {
        case .grinder: pool = grinders.map(Item.init)
        case .brewer:
            var items = brewers.map(Item.init)
            let seeded = Set(items.map(\.id))
            items += kit.filter { $0.kind == .brewer && !seeded.contains($0.id) }
            pool = items
        default:
            pool = kit.filter { $0.kind == kind }
        }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let matched = trimmed.isEmpty
            ? pool
            : pool.filter {
                $0.displayName.localizedCaseInsensitiveContains(trimmed)
                    || $0.brand.localizedCaseInsensitiveContains(trimmed)
                    || $0.model.localizedCaseInsensitiveContains(trimmed)
                    || ($0.variant?.localizedCaseInsensitiveContains(trimmed) ?? false)
            }
        return Array(matched)
    }

    private static func load<T: Decodable>(_ name: String) -> [T] {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json") else {
            Log.app.error("reference base \(name).json is missing from the bundle")
            return []
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([T].self, from: data)
        } catch {
            Log.app.error("could not read \(name).json: \(error)")
            return []
        }
    }
}

extension Equipment {
    /// From the reference seed. A grinder typed by hand has no row, so this stays nil.
    var isManual: Bool? {
        guard let grinderRef else { return nil }
        return ReferenceBase.grinder(id: grinderRef)?.isManual
    }

    /// A grinder pre-filled from the reference base. Everything the base knows
    /// is copied in, so the record stays readable if the base later changes.
    init(reference: ReferenceBase.Grinder) {
        self.init(
            kind: .grinder,
            brand: reference.brand,
            model: reference.model,
            grinderRef: reference.id,
            burrType: reference.burrType,
            burrMm: reference.burrMm,
            adjustment: reference.adjustment,
            stepsPerRotation: reference.stepsPerRotation,
            makerMicronsPerStep: reference.makerMicronsPerStep,
            ranges: reference.ranges ?? []
        )
    }

    /// A brewer, kettle, scale or machine from the kit catalogue.
    init(reference: ReferenceBase.Brewer, preserving draft: Equipment? = nil) {
        let filters = (reference.filter?.isEmpty == false)
            ? [BrewFilter(brand: reference.brand, shape: reference.filter ?? "")]
            : (draft?.filters ?? [])
        let kit = {
            let fromSeed = reference.filterShapes
            if !fromSeed.isEmpty { return (size: FilterShape.kit(from: reference.filter, model: reference.model).size, shapes: fromSeed) }
            if reference.declaresNoPaper { return (size: String?.none, shapes: [FilterShape]()) }
            return FilterShape.kit(from: reference.filter, model: reference.model)
        }()
        self.init(
            id: draft?.id ?? UUID(),
            kind: .brewer,
            brand: reference.brand,
            model: reference.model,
            notes: draft?.notes ?? (reference.note ?? ""),
            isDefaultFor: draft?.isDefaultFor ?? [],
            brewerRef: reference.id,
            brewerType: reference.dripperFamily.brewerType.storageValue,
            filters: filters,
            defaultFilterId: filters.first?.id,
            size: kit.size ?? draft?.size,
            acceptsFilterShapes: kit.shapes.isEmpty ? (draft?.acceptsFilterShapes ?? []) : kit.shapes,
            createdAt: draft?.createdAt ?? .now
        )
    }

    /// A brewer, kettle, scale or machine from the kit catalogue.
    init(reference: ReferenceBase.Item, preserving draft: Equipment? = nil) {
        let variant = reference.variant?.trimmingCharacters(in: .whitespaces) ?? ""
        let model = variant.isEmpty ? reference.model : "\(reference.model) \(variant)"
        let filters = (reference.filters ?? []).map {
            BrewFilter(brand: $0.brand, shape: $0.shape)
        }
        let kit = FilterShape.kit(
            from: reference.filters?.first?.shape,
            model: reference.model
        )
        self.init(
            id: draft?.id ?? UUID(),
            kind: reference.kind,
            brand: reference.brand,
            model: model,
            notes: draft?.notes ?? "",
            isDefaultFor: draft?.isDefaultFor ?? [],
            grinderRef: draft?.grinderRef,
            brewerRef: draft?.brewerRef ?? (
                reference.kind == .brewer || reference.kind == .espressoMachine ? reference.id : nil
            ),
            burrType: draft?.burrType,
            burrMm: draft?.burrMm,
            adjustment: draft?.adjustment,
            stepsPerRotation: draft?.stepsPerRotation,
            makerMicronsPerStep: draft?.makerMicronsPerStep,
            ranges: draft?.ranges ?? [],
            brewerType: reference.family?.storageValue,
            filters: filters,
            defaultFilterId: filters.first?.id,
            size: kit.size ?? draft?.size,
            acceptsFilterShapes: kit.shapes.isEmpty ? (draft?.acceptsFilterShapes ?? []) : kit.shapes,
            basketG: reference.basketG,
            pressureBar: reference.pressureBar,
            isGooseneck: reference.isGooseneck,
            hasTemperatureControl: reference.hasTemperatureControl,
            resolutionG: reference.resolutionG,
            hasTimer: reference.hasTimer,
            createdAt: draft?.createdAt ?? .now
        )
    }
}

extension WaterProfile {
    init(reference: ReferenceBase.Water) {
        self.init(
            name: reference.name,
            source: .bottled,
            tds: reference.tds,
            calcium: reference.calcium,
            magnesium: reference.magnesium,
            sodium: reference.sodium,
            bicarbonate: reference.bicarbonate,
            notes: reference.note ?? "",
            waterRef: reference.id
        )
    }
}
