import Foundation

/// DTO matching the `public.equipment` table schema (snake_case).
///
/// Per-kind fields that only ever matter together — burr geometry, filter,
/// basket — stay as columns, because filtering on them later is worth more
/// than the tidiness of a bag. `ranges` is jsonb: it is a list, and it is only
/// ever read as a whole.
struct EquipmentRow: Codable, Sendable {
    let id: UUID
    let user_id: UUID

    var kind: String
    var brand: String
    var model: String
    var notes: String
    var is_default_for: [String]

    var grinder_ref: String?
    var brewer_ref: String?
    var burr_type: String?
    var burr_mm: Double?
    var adjustment: String?
    var steps_per_rotation: Int?
    var maker_microns_per_step: Double?
    var ranges: [GrindRange]

    var brewer_type: String?
    var filter_brand: String?
    var filter_shape: String?
    var filters: [BrewFilter]?
    var default_filter_id: UUID?
    var size: String?
    var accepts_filter_shapes: [String]?

    var basket_g: Double?
    var pressure_bar: Double?

    var is_gooseneck: Bool?
    var has_temperature_control: Bool?

    var resolution_g: Double?
    var has_timer: Bool?

    var created_at: Date
    var updated_at: Date

    init(equipment: Equipment, userID: UUID) {
        self.id = equipment.id
        self.user_id = userID
        self.kind = equipment.kind.rawValue
        self.brand = equipment.brand
        self.model = equipment.model
        self.notes = equipment.notes
        self.is_default_for = equipment.isDefaultFor.map(\.rawValue)
        self.grinder_ref = equipment.grinderRef
        self.brewer_ref = equipment.brewerRef
        self.burr_type = equipment.burrType?.rawValue
        self.burr_mm = equipment.burrMm
        self.adjustment = equipment.adjustment?.rawValue
        self.steps_per_rotation = equipment.stepsPerRotation
        self.maker_microns_per_step = equipment.makerMicronsPerStep
        self.ranges = equipment.ranges
        self.brewer_type = equipment.brewerType
        self.filter_brand = equipment.filterBrand
        self.filter_shape = equipment.filterShape
        self.filters = equipment.filters
        self.default_filter_id = equipment.defaultFilterId
        self.size = equipment.size
        self.accepts_filter_shapes = equipment.acceptsFilterShapes.map(\.rawValue)
        self.basket_g = equipment.basketG
        self.pressure_bar = equipment.pressureBar
        self.is_gooseneck = equipment.isGooseneck
        self.has_temperature_control = equipment.hasTemperatureControl
        self.resolution_g = equipment.resolutionG
        self.has_timer = equipment.hasTimer
        self.created_at = equipment.createdAt
        self.updated_at = equipment.updatedAt
    }

    func toEquipment() -> Equipment {
        Equipment(
            id: id,
            kind: EquipmentKind(rawValue: kind) ?? .accessory,
            brand: brand,
            model: model,
            notes: notes,
            isDefaultFor: is_default_for.compactMap { BrewMethod(rawValue: $0) },
            grinderRef: grinder_ref,
            brewerRef: brewer_ref,
            burrType: burr_type.flatMap { BurrType(rawValue: $0) },
            burrMm: burr_mm,
            adjustment: adjustment.flatMap { GrindAdjustment(rawValue: $0) },
            stepsPerRotation: steps_per_rotation,
            makerMicronsPerStep: maker_microns_per_step,
            ranges: ranges,
            brewerType: brewer_type,
            filterBrand: filter_brand,
            filterShape: filter_shape,
            filters: filters ?? [],
            defaultFilterId: default_filter_id,
            size: size,
            acceptsFilterShapes: (accepts_filter_shapes ?? []).compactMap(FilterShape.init(rawValue:)),
            basketG: basket_g,
            pressureBar: pressure_bar,
            isGooseneck: is_gooseneck,
            hasTemperatureControl: has_temperature_control,
            resolutionG: resolution_g,
            hasTimer: has_timer,
            createdAt: created_at,
            updatedAt: updated_at
        )
    }
}

/// DTO matching the `public.grind_calibrations` table schema (snake_case).
struct GrindCalibrationRow: Codable, Sendable {
    let id: UUID
    let user_id: UUID

    var grinder_id: UUID
    var method: String
    var setting: Double
    var microns_proxy: Double?
    var note: String
    var created_at: Date
    var updated_at: Date

    init(calibration: GrindCalibration, userID: UUID) {
        self.id = calibration.id
        self.user_id = userID
        self.grinder_id = calibration.grinderID
        self.method = calibration.method.rawValue
        self.setting = calibration.setting
        self.microns_proxy = calibration.micronsProxy
        self.note = calibration.note
        self.created_at = calibration.createdAt
        self.updated_at = calibration.updatedAt
    }

    func toCalibration() -> GrindCalibration {
        GrindCalibration(
            id: id,
            grinderID: grinder_id,
            method: BrewMethod(rawValue: method) ?? .v60,
            setting: setting,
            micronsProxy: microns_proxy,
            note: note,
            createdAt: created_at,
            updatedAt: updated_at
        )
    }
}

/// DTO matching the `public.water_profiles` table schema (snake_case).
/// Hardness and alkalinity are not columns: they are derived from the ions, and
/// storing a derived value is how the two drift apart.
struct WaterProfileRow: Codable, Sendable {
    let id: UUID
    let user_id: UUID

    var name: String
    var source: String
    var tds: Double?
    var calcium: Double?
    var magnesium: Double?
    var sodium: Double?
    var bicarbonate: Double?
    var additive_name: String?
    var additive_dose: String?
    var mineral_product_id: String?
    var filtration_system: String?
    var water_base: String?
    var notes: String
    var is_default: Bool
    var water_ref: String?
    var created_at: Date
    var updated_at: Date

    init(profile: WaterProfile, userID: UUID) {
        self.id = profile.id
        self.user_id = userID
        self.name = profile.name
        self.source = profile.source.rawValue
        self.tds = profile.tds
        self.calcium = profile.calcium
        self.magnesium = profile.magnesium
        self.sodium = profile.sodium
        self.bicarbonate = profile.bicarbonate
        self.additive_name = profile.additiveName
        self.additive_dose = profile.additiveDose
        self.mineral_product_id = profile.mineralProductID
        self.filtration_system = profile.filtrationSystem?.rawValue
        self.water_base = profile.waterBase?.rawValue
        self.notes = profile.notes
        self.is_default = profile.isDefault
        self.water_ref = profile.waterRef
        self.created_at = profile.createdAt
        self.updated_at = profile.updatedAt
    }

    func toWaterProfile() -> WaterProfile {
        WaterProfile(
            id: id,
            name: name,
            source: WaterSource(rawValue: source) ?? .tap,
            tds: tds,
            calcium: calcium,
            magnesium: magnesium,
            sodium: sodium,
            bicarbonate: bicarbonate,
            additiveName: additive_name,
            additiveDose: additive_dose,
            mineralProductID: mineral_product_id,
            filtrationSystem: filtration_system.flatMap(FiltrationSystem.init(rawValue:)),
            waterBase: water_base.flatMap(WaterBase.init(rawValue:)),
            notes: notes,
            isDefault: is_default,
            waterRef: water_ref,
            createdAt: created_at,
            updatedAt: updated_at
        )
    }
}

/// DTO matching the `public.filter_stock` table schema (snake_case).
struct FilterStockRow: Codable, Sendable {
    let id: UUID
    let user_id: UUID

    var model_id: String?
    var custom_name: String?
    var size: String
    var origin: String?
    var shape: String?
    var is_default_for: [UUID]
    var created_at: Date
    var updated_at: Date

    init(stock: FilterStock, userID: UUID) {
        self.id = stock.id
        self.user_id = userID
        self.model_id = stock.modelId
        self.custom_name = stock.customName
        self.size = stock.size
        self.origin = stock.origin
        self.shape = stock.shape?.rawValue
        self.is_default_for = stock.isDefaultFor
        self.created_at = stock.createdAt
        self.updated_at = stock.updatedAt
    }

    func toStock() -> FilterStock {
        FilterStock(
            id: id,
            modelId: model_id,
            customName: custom_name,
            size: size,
            origin: origin,
            shape: shape.flatMap(FilterShape.init(rawValue:)),
            isDefaultFor: is_default_for,
            createdAt: created_at,
            updatedAt: updated_at
        )
    }
}
