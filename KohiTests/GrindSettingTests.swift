import Foundation
import Testing
@testable import Kohi

struct GrindSettingTests {
    @Test func clicksParseIntoAValue() {
        let setting = GrindSetting(raw: "22 clicks")

        #expect(setting.value == 22)
        #expect(setting.raw == "22 clicks")
        #expect(setting.display() == "22 clicks")
    }

    @Test func aBareNumberIsAValue() {
        let setting = GrindSetting(raw: "2.4")

        #expect(setting.value == 2.4)
    }

    @Test func aVerbalSettingHasNoNumber() {
        let setting = GrindSetting(raw: "medium-fine")

        #expect(setting.value == nil)
        #expect(setting.raw == "medium-fine")
        #expect(setting.display() == "medium-fine")
        #expect(!setting.isEmpty)
        #expect(GrindGrade.parse("medium-fine") == .mediumFine)
        #expect(GrindGrade.parse("medium fine") == .mediumFine)
        #expect(GrindGrade.nearest(position: 0) == .extraFine)
        #expect(GrindGrade.nearest(position: 1) == .extraCoarse)
    }

    @Test func aClickyGrinderGetsANumericSpan() {
        let mill = Equipment(
            kind: .grinder,
            brand: "1Zpresso",
            model: "J-Ultra",
            adjustment: .clicks,
            stepsPerRotation: 100,
            ranges: [GrindRange(method: .v60, low: 18, high: 36)]
        )
        let span = GrindSpan.make(grinder: mill, method: .v60, current: nil)
        #expect(span?.band == 18...36)
        #expect(span?.step == 1)
        #expect(span?.unit == "clicks")
        #expect(span?.low ?? 0 < 18)
        #expect(span?.high ?? 0 > 36)
        #expect(span?.snap(22.4) == 22)
        #expect(GrindSpan.stepSize(for: mill) == 1)
    }

    @Test func aVerbalGrindStaysAGradeWithoutAGrinder() {
        #expect(GrindSpan.make(grinder: nil, method: .v60, current: nil) == nil)
        #expect(GrindGrade.parse("coarse") == .coarse)
    }

    @Test func emptyTextIsEmpty() {
        #expect(GrindSetting(raw: "  ").isEmpty)
        #expect(GrindSetting().isEmpty)
    }

    @Test func aStringLiteralStillBuildsABrew() {
        let brew = Brew(grind: "22 clicks")
        #expect(brew.grind.value == 22)
    }

    @Test func decodingAStringLiftsIt() throws {
        let data = Data(#""18 clicks""#.utf8)
        let setting = try JSONDecoder().decode(GrindSetting.self, from: data)
        #expect(setting.value == 18)
        #expect(setting.raw == "18 clicks")
    }

    @Test func decodingAnObjectKeepsThePieces() throws {
        let data = Data(#"{"grinderId":null,"value":22,"raw":"22 clicks"}"#.utf8)
        let setting = try JSONDecoder().decode(GrindSetting.self, from: data)
        #expect(setting.value == 22)
        #expect(setting.raw == "22 clicks")
    }

    @Test func micronsProxyUsesTheMakersStep() {
        var grinder = Equipment(kind: .grinder, brand: "Comandante", model: "C40")
        grinder.makerMicronsPerStep = 30
        let setting = GrindSetting(value: 20)

        #expect(setting.micronsProxy(grinder: grinder, calibrations: [], method: .v60) == 600)
        #expect(setting.micronsLabel(grinder: grinder, calibrations: [], method: .v60) == "≈ 600 µm")
    }

    @Test func aPersonalCalibrationBeatsTheMakerStep() {
        var grinder = Equipment(kind: .grinder, brand: "Comandante", model: "C40")
        grinder.makerMicronsPerStep = 30
        let calibration = GrindCalibration(
            grinderID: grinder.id,
            method: .v60,
            setting: 22,
            micronsProxy: 440
        )
        let setting = GrindSetting(grinderId: grinder.id, value: 11)

        let microns = setting.micronsProxy(grinder: grinder, calibrations: [calibration], method: .v60)
        #expect(microns == 220)
    }
}
