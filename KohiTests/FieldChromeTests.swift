import Foundation
import SwiftUI
import Testing
import UIKit
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

    @Test func aMissingFieldTurnsCoffeeBrown() {
        for focused in [false, true] {
            let rule = FieldChrome.rule(presence: .useful, isEmpty: true, isFocused: focused, hasError: true)
            #expect(rule.tone == .primary)
            #expect(rule.opacity == 1)
            #expect(FieldChrome.label(presence: .optional, isEmpty: true, isFocused: focused, hasError: true) == .primary)
        }
        #expect(FieldTone.primary.color == Palette.primary)
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

    @Test func comparisonTokensMatchTheAgreedHex() {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        #expect(UIColor(Palette.primary).getRed(&r, green: &g, blue: &b, alpha: &a))
        #expect(abs(r - 130 / 255) < 0.01)
        #expect(abs(g - 78 / 255) < 0.01)
        #expect(abs(b - 52 / 255) < 0.01)

        #expect(UIColor(Palette.secondary).getRed(&r, green: &g, blue: &b, alpha: &a))
        #expect(abs(r - 61 / 255) < 0.01)
        #expect(abs(g - 92 / 255) < 0.01)
        #expect(abs(b - 86 / 255) < 0.01)
        #expect(Palette.primary != Palette.secondary)
    }

    @Test func recipeParameterLabelsFitTheCatalogueColumn() {
        let labels = [Copy.coffeeDose, Copy.waterWeight, Copy.totalBrewTime, Copy.forYourGrinder]
        for label in labels {
            let width = catalogueWidth(label)
            #expect(
                width <= CatalogueRow.labelColumn,
                "\(label) needs \(width) pt, column is \(CatalogueRow.labelColumn)"
            )
        }
    }

    private func catalogueWidth(_ text: String) -> CGFloat {
        let font = UIFont.monospacedSystemFont(ofSize: 10, weight: .medium)
        return ceil(
            (text.uppercased() as NSString).size(withAttributes: [
                .font: font,
                .kern: Typography.labelTracking
            ]).width
        )
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
