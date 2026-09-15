import Foundation
import Testing
@testable import Kohi

struct FieldChromeTests {
    @Test func anEmptyOptionalRowGhosts() {
        let label = FieldChrome.label(presence: .optional, isEmpty: true, isFocused: false)
        let rule = FieldChrome.rule(presence: .optional, isEmpty: true, isFocused: false, hasError: false)
        #expect(label == .hairline)
        #expect(FieldChrome.placeholder() == .hairline)
        #expect(rule.tone == .hairline)
        #expect(rule.opacity == Motion.Field.optionalRuleOpacity)
    }

    @Test func anEmptyUsefulRowKeepsItsLabel() {
        let label = FieldChrome.label(presence: .useful, isEmpty: true, isFocused: false)
        let rule = FieldChrome.rule(presence: .useful, isEmpty: true, isFocused: false, hasError: false)
        #expect(label == .inkMuted)
        #expect(FieldChrome.placeholder() == .hairline)
        #expect(rule.tone == .hairline)
        #expect(rule.opacity == 1)
    }

    @Test func aFilledRowIsTheDocument() {
        for presence in [FieldPresence.optional, .useful] {
            let label = FieldChrome.label(presence: presence, isEmpty: false, isFocused: false)
            let rule = FieldChrome.rule(presence: presence, isEmpty: false, isFocused: false, hasError: false)
            #expect(label == .inkMuted)
            #expect(rule.tone == .hairline)
            #expect(rule.opacity == 1)
        }
    }

    @Test func focusTurnsTheRuleToInk() {
        let rule = FieldChrome.rule(presence: .optional, isEmpty: true, isFocused: true, hasError: false)
        #expect(rule.tone == .ink)
        #expect(rule.opacity == 1)
        #expect(FieldChrome.label(presence: .optional, isEmpty: true, isFocused: true) == .inkMuted)
    }

    @Test func anErrorKeepsTheRuleInInkWithoutFocus() {
        let rule = FieldChrome.rule(presence: .useful, isEmpty: false, isFocused: false, hasError: true)
        #expect(rule.tone == .ink)
        #expect(rule.opacity == 1)
    }

    @Test func aUnitGhostsUntilThereIsANumber() {
        #expect(FieldChrome.unit(isEmpty: true) == .hairline)
        #expect(FieldChrome.unit(isEmpty: false) == .inkMuted)
    }

    @Test func boilingIsNamedNotColoured() {
        #expect(FieldCopy.boiling(94) == nil)
        #expect(FieldCopy.boiling(100) == nil)
        #expect(FieldCopy.boiling(104) == "104 °C is past boiling")
    }

    @Test func originFoldsWhenNothingIsInIt() {
        #expect(!CoffeeCard().hasOrigin)
        #expect(CoffeeCard().originSummary == nil)

        let card = CoffeeCard(country: "Ethiopia", region: "Gedeb", producer: "Smallholders")
        #expect(card.hasOrigin)
        #expect(card.originSummary == "Ethiopia · Gedeb · Smallholders")
    }

    @Test func altitudeAloneStillOpensOrigin() {
        let card = CoffeeCard(altitude: "1,900 m")
        #expect(card.hasOrigin)
        #expect(card.originSummary == nil)
    }
}
