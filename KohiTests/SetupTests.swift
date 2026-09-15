import Foundation
import Testing

@testable import Kohi

struct SetupTests {
    // MARK: - Water chemistry

    @Test func hardnessFollowsTheCalciumAndMagnesiumFormula() {
        // Montcalm, off the label: Ca 3, Mg 0.7.
        let water = WaterProfile(calcium: 3, magnesium: 0.7)
        #expect(water.generalHardness == 2.50 * 3 + 4.12 * 0.7)
    }

    @Test func alkalinityFollowsTheBicarbonateFormula() {
        let water = WaterProfile(bicarbonate: 50)
        #expect(water.alkalinity == 0.82 * 50)
    }

    /// A missing measurement has to stay missing. Reading nil as zero would
    /// print "GH 0" for a water nobody has measured, which is a claim.
    @Test func unmeasuredWaterHasNoHardness() {
        #expect(WaterProfile().generalHardness == nil)
        #expect(WaterProfile().alkalinity == nil)
    }

    @Test func oneKnownIonIsEnoughForHardness() {
        let water = WaterProfile(calcium: 20)
        #expect(water.generalHardness == 50)
    }

    @Test func summaryDropsWhatIsUnknown() {
        #expect(WaterProfile(source: .filtered).summary == "Filtered")
        #expect(WaterProfile(tds: 150).summary == "150 ppm")
    }

    // MARK: - Grind ranges

    @Test func aRangeStoresItselfInOrder() {
        let range = GrindRange(method: .v60, low: 26, high: 20)
        #expect(range.low == 20)
        #expect(range.high == 26)
        #expect(range.label == "20–26")
    }

    @Test func aSingleSettingReadsAsOneNumber() {
        #expect(GrindRange(method: .espresso, low: 9, high: 9).label == "9")
    }

    @Test func decimalsSurviveForSteplessGrinders() {
        #expect(GrindRange.number(4.5) == "4.5")
        #expect(GrindRange.number(4.0) == "4")
    }

    // MARK: - Store

    private func emptyStore() -> SetupStore {
        SetupStore(files: JSONDocumentStore(filename: "setup-test-\(UUID().uuidString).json"))
    }

    private func grinder(_ model: String) -> Equipment {
        Equipment(kind: .grinder, brand: "1Zpresso", model: model, adjustment: .clicks)
    }

    @Test func oneDefaultPerKindPerMethod() {
        let store = emptyStore()
        let first = grinder("J-Ultra")
        let second = grinder("K-Ultra")
        store.add(first)
        store.add(second)

        store.setDefault(first, for: .v60, on: true)
        store.setDefault(second, for: .v60, on: true)

        // Setting the second one has to release the first, or the brew sheet
        // has two grinders and no way to choose.
        #expect(store.equipment(id: first.id)?.isDefaultFor == [])
        #expect(store.equipment(id: second.id)?.isDefaultFor == [.v60])
        #expect(store.defaults(for: .v60).map(\.id) == [second.id])
    }

    @Test func defaultsForOneMethodLeaveAnotherAlone() {
        let store = emptyStore()
        let espresso = grinder("J-Ultra")
        let filter = grinder("K-Ultra")
        store.add(espresso)
        store.add(filter)

        store.setDefault(espresso, for: .espresso, on: true)
        store.setDefault(filter, for: .v60, on: true)

        #expect(store.defaults(for: .espresso).map(\.id) == [espresso.id])
        #expect(store.defaults(for: .v60).map(\.id) == [filter.id])
    }

    @Test func defaultsReturnOneItemOfEachKind() {
        let store = emptyStore()
        let mill = grinder("J-Ultra")
        let brewer = Equipment(kind: .brewer, brand: "Hario", model: "V60 02")
        store.add(mill)
        store.add(brewer)
        store.setDefault(mill, for: .v60, on: true)
        store.setDefault(brewer, for: .v60, on: true)

        #expect(store.defaults(for: .v60).count == 2)
        #expect(Set(store.defaults(for: .v60).map(\.kind)) == [.grinder, .brewer])
    }

    @Test func theFirstWaterBecomesTheDefault() {
        let store = emptyStore()
        store.add(WaterProfile(name: "Tap"))
        #expect(store.waterProfiles.first?.isDefault == true)

        store.add(WaterProfile(name: "Montcalm"))
        // A second one does not steal the role.
        #expect(store.waterProfiles.filter(\.isDefault).count == 1)
        #expect(store.defaultWaterProfile?.name == "Tap")
    }

    @Test func deletingTheDefaultWaterPromotesAnother() {
        let store = emptyStore()
        store.add(WaterProfile(name: "Tap"))
        store.add(WaterProfile(name: "Montcalm"))
        guard let first = store.waterProfiles.first else {
            Issue.record("the store lost the profile it was just given")
            return
        }

        store.delete(first)
        #expect(store.waterProfiles.count == 1)
        #expect(store.defaultWaterProfile?.name == "Montcalm")
    }

    @Test func makingOneWaterTheDefaultClearsTheOther() {
        let store = emptyStore()
        store.add(WaterProfile(name: "Tap"))
        store.add(WaterProfile(name: "Montcalm"))
        guard let second = store.waterProfiles.last else {
            Issue.record("the store lost the profile it was just given")
            return
        }

        store.makeDefault(second)
        #expect(store.waterProfiles.filter(\.isDefault).map(\.name) == ["Montcalm"])
    }

    @Test func setRangeReplacesTheRangeForThatMethod() {
        let store = emptyStore()
        let mill = grinder("J-Ultra")
        store.add(mill)

        store.setRange(GrindRange(method: .v60, low: 20, high: 26), on: mill)
        store.setRange(GrindRange(method: .v60, low: 22, high: 28), on: mill)
        store.setRange(GrindRange(method: .espresso, low: 8, high: 12), on: mill)

        let stored = store.equipment(id: mill.id)
        #expect(stored?.ranges.count == 2)
        #expect(stored?.range(for: .v60)?.label == "22–28")
    }

    @Test func preferredGrinderPrefersTheMethodDefaultOverTheOnlyGrinder() {
        let store = emptyStore()
        let one = grinder("J-Ultra")
        let two = grinder("K-Ultra")
        store.add(one)
        store.add(two)

        // Two grinders and no default: nothing to guess from.
        #expect(store.preferredGrinder(for: .v60) == nil)

        store.setDefault(two, for: .v60, on: true)
        #expect(store.preferredGrinder(for: .v60)?.id == two.id)
    }

    @Test func aSingleGrinderIsPreferredWithoutBeingMarked() {
        let store = emptyStore()
        let only = grinder("J-Ultra")
        store.add(only)
        #expect(store.preferredGrinder(for: .aeropress)?.id == only.id)
    }

    // MARK: - Merge

    @Test func mergeKeepsTheNewerEdit() {
        let store = emptyStore()
        var local = grinder("J-Ultra")
        local.updatedAt = Date(timeIntervalSince1970: 2_000)
        store.add(local)

        var stale = local
        stale.model = "from another device"
        stale.updatedAt = Date(timeIntervalSince1970: 1_000)
        store.merge(equipment: [stale])
        #expect(store.equipment(id: local.id)?.model == "J-Ultra")

        var fresh = local
        fresh.model = "K-Ultra"
        fresh.updatedAt = Date(timeIntervalSince1970: 3_000)
        store.merge(equipment: [fresh])
        #expect(store.equipment(id: local.id)?.model == "K-Ultra")
    }

    @Test func mergeAddsRecordsThisDeviceHasNeverSeen() {
        let store = emptyStore()
        let remote = WaterProfile(name: "Montcalm", source: .bottled)
        store.merge(waterProfiles: [remote])
        #expect(store.waterProfile(id: remote.id)?.name == "Montcalm")
    }

    // MARK: - Reference base

    /// The gate from the PRD: nothing unverified gets seeded. The rows carry
    /// maker step sizes, never invented grind ranges.
    @Test func theGrinderBaseIsLoadableAndCited() {
        #expect(!ReferenceBase.grinders.isEmpty)
        for grinder in ReferenceBase.grinders {
            #expect(!grinder.brand.isEmpty)
            #expect(!grinder.model.isEmpty)
            #expect(grinder.source?.isEmpty == false)
        }
    }

    @Test func theWaterBaseIsLoadableAndCited() {
        #expect(!ReferenceBase.waters.isEmpty)
        for water in ReferenceBase.waters {
            #expect(water.source?.isEmpty == false)
        }
    }

    @Test func pickingAReferenceGrinderFillsWhatTheConversionNeeds() throws {
        let reference = try #require(ReferenceBase.grinder(id: "1zpresso-j-ultra"))
        let equipment = Equipment(reference: reference)

        #expect(equipment.kind == .grinder)
        #expect(equipment.brand == "1Zpresso")
        #expect(equipment.adjustment == .clicks)
        #expect(equipment.makerMicronsPerStep == 8)
        #expect(equipment.grinderRef == "1zpresso-j-ultra")
    }

    @Test func referenceSearchMatchesBrandOrModel() {
        #expect(!ReferenceBase.grinders(matching: "1zpresso").isEmpty)
        #expect(!ReferenceBase.grinders(matching: "encore").isEmpty)
        #expect(ReferenceBase.grinders(matching: "not a grinder").isEmpty)
    }

    // MARK: - Row parity

    private func fullEquipment() -> Equipment {
        Equipment(
            kind: .grinder,
            brand: "1Zpresso",
            model: "J-Ultra",
            notes: "clicks from zero, retention is low",
            isDefaultFor: [.v60, .espresso],
            grinderRef: "1zpresso-j-ultra",
            burrType: .conical,
            burrMm: 48,
            adjustment: .clicks,
            stepsPerRotation: 100,
            makerMicronsPerStep: 8,
            ranges: [
                GrindRange(method: .v60, low: 20, high: 26),
                GrindRange(method: .espresso, low: 8, high: 12),
            ],
            brewerType: "Pour-over",
            filterBrand: "Hario tabbed",
            filterShape: "Cone 02",
            filters: [
                BrewFilter(
                    id: UUID(uuidString: "EEEEEEEE-0000-0000-0000-000000000006")!,
                    brand: "Hario tabbed",
                    shape: "Cone 02"
                ),
            ],
            defaultFilterId: UUID(uuidString: "EEEEEEEE-0000-0000-0000-000000000006")!,
            basketG: 18,
            pressureBar: 9,
            isGooseneck: true,
            hasTemperatureControl: true,
            resolutionG: 0.1,
            hasTimer: true,
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 2_000)
        )
    }

    private func fullWater() -> WaterProfile {
        WaterProfile(
            name: "Montcalm + TWW",
            source: .recipe,
            tds: 150,
            calcium: 3,
            magnesium: 0.7,
            sodium: 2.2,
            bicarbonate: 5.2,
            additiveName: "Third Wave Water — Classic",
            additiveDose: "1 sachet / 1 L",
            notes: "sweeter on washed Ethiopias",
            isDefault: true,
            waterRef: "montcalm",
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 2_000)
        )
    }

    @Test func equipmentSurvivesTheRowRoundTrip() {
        let original = fullEquipment()
        let restored = EquipmentRow(equipment: original, userID: UUID()).toEquipment()
        #expect(restored == original)
    }

    @Test func waterSurvivesTheRowRoundTrip() {
        let original = fullWater()
        let restored = WaterProfileRow(profile: original, userID: UUID()).toWaterProfile()
        #expect(restored == original)
    }

    /// The parity census: a property added to the model without a column and a
    /// mapping fails here rather than silently never reaching Supabase.
    @Test func equipmentPropertiesAreAllAccountedFor() {
        let mapped: Set<String> = [
            "id", "kind", "brand", "model", "notes", "isDefaultFor",
            "grinderRef", "brewerRef", "burrType", "burrMm", "adjustment", "stepsPerRotation",
            "makerMicronsPerStep", "ranges",
            "brewerType", "filterBrand", "filterShape", "filters", "defaultFilterId",
            "basketG", "pressureBar",
            "isGooseneck", "hasTemperatureControl",
            "resolutionG", "hasTimer",
            "createdAt", "updatedAt",
        ]
        let actual = Set(Mirror(reflecting: fullEquipment()).children.compactMap(\.label))
        #expect(actual.subtracting(mapped).isEmpty, "unmapped Equipment properties")
    }

    @Test func waterProfilePropertiesAreAllAccountedFor() {
        let mapped: Set<String> = [
            "id", "name", "source", "tds", "calcium", "magnesium", "sodium",
            "bicarbonate", "additiveName", "additiveDose", "mineralProductID",
            "filtrationSystem", "waterBase", "notes", "isDefault",
            "waterRef", "createdAt", "updatedAt",
        ]
        let actual = Set(Mirror(reflecting: fullWater()).children.compactMap(\.label))
        #expect(actual.subtracting(mapped).isEmpty, "unmapped WaterProfile properties")
    }

    // MARK: - Tolerant decoding

    @Test func anEquipmentRecordFromAnOlderBuildStillDecodes() throws {
        let json = Data(#"{"kind":"grinder","brand":"Comandante"}"#.utf8)
        let equipment = try JSONDecoder().decode(Equipment.self, from: json)
        #expect(equipment.brand == "Comandante")
        #expect(equipment.ranges.isEmpty)
        #expect(equipment.isDefaultFor.isEmpty)
    }

    @Test func aMissingFilterListIsLiftedFromBrandAndShape() throws {
        let json = Data(#"{"kind":"brewer","filterBrand":"Hario","filterShape":"Cone 02"}"#.utf8)
        let equipment = try JSONDecoder().decode(Equipment.self, from: json)
        #expect(equipment.filters.count == 1)
        #expect(equipment.filters[0].brand == "Hario")
        #expect(equipment.filters[0].shape == "Cone 02")
    }

    @Test func anEmptyFilterListIsNotReinventedOnLoad() throws {
        let json = Data(#"{"kind":"brewer","filterBrand":"Hario","filterShape":"Cone 02","filters":[]}"#.utf8)
        let equipment = try JSONDecoder().decode(Equipment.self, from: json)
        #expect(equipment.filters.isEmpty)
    }

    @Test func aWaterRecordFromAnOlderBuildStillDecodes() throws {
        let json = Data(#"{"name":"Tap"}"#.utf8)
        let water = try JSONDecoder().decode(WaterProfile.self, from: json)
        #expect(water.name == "Tap")
        #expect(water.source == .tap)
    }

    @Test func aWaterRowFromBeforeRecipeModeStillDecodes() throws {
        let data = try JSONEncoder().encode(WaterProfileRow(profile: fullWater(), userID: UUID()))
        var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        object.removeValue(forKey: "mineral_product_id")
        object.removeValue(forKey: "filtration_system")
        object.removeValue(forKey: "water_base")
        let restored = try JSONDecoder().decode(
            WaterProfileRow.self,
            from: try JSONSerialization.data(withJSONObject: object)
        ).toWaterProfile()
        #expect(restored.mineralProductID == nil)
        #expect(restored.filtrationSystem == nil)
        #expect(restored.waterBase == nil)
    }
}
