import SwiftUI
import Testing
@testable import Kohi

/// 21 November: the flavours of a family sit flat under it, groups and
/// their flavours alike. No chevron to find under a chip's touch area.
@MainActor
struct FlatFlavorsTests {
    @Test func everyFlavourOfTheWheelIsInViewUnderItsFamily() {
        let wheel = FlavorWheel.shared
        for family in wheel.families {
            let shown = FlavorFamilyLayout.entries(of: family.id).map(\.id)
            let groups = wheel.children(of: family.id)
            let expected = groups.flatMap { [$0.id] + wheel.children(of: $0.id).map(\.id) }
            #expect(shown == expected, "\(family.id)")
        }
    }

    @Test func berriesSitUnderFruity() throws {
        let fruity = try #require(FlavorWheel.shared.families.first { $0.en.lowercased() == "fruity" })
        let names = FlavorFamilyLayout.entries(of: fruity.id)
            .compactMap { FlavorWheel.shared.node(id: $0.id)?.en }
        for name in ["Berry", "Blackberry", "Raspberry"] {
            #expect(names.contains(name), "\(name)")
        }
    }

    @Test func onlyAGroupAfterTheFirstOpensAGap() {
        let family = FlavorWheel.shared.families[0]
        let entries = FlavorFamilyLayout.entries(of: family.id)
        let groups = Set(FlavorWheel.shared.children(of: family.id).map(\.id))
        #expect(entries.first?.opensGroup == false)
        for entry in entries.dropFirst() {
            #expect(entry.opensGroup == groups.contains(entry.id))
        }
    }

    @Test func thePickerHasNoChevronPerGroup() throws {
        let source = try String(
            contentsOf: DevBrief10.kohiRoot.appending(path: "Edit/FlavorPicker.swift"),
            encoding: .utf8
        )
        #expect(!source.contains("expanded"))
        #expect(source.components(separatedBy: "chevron.right").count == 2, "only the All row keeps one")
        #expect(source.contains("FlavorFamilyLayout.entries(of: family.id)"))
    }
}

@Suite(.serialized)
@MainActor
struct FlatFlavorsSnapshotTests {
    @Test func theWheelOpensFlat() {
        SnapshotSupport.image(
            of: FlavorPicker(
                selection: .constant([FlavorTag(id: "fruity-berry-raspberry")]),
                showsSummary: false,
                opensAll: true
            )
            .padding(26),
            height: 2400,
            named: "flat-wheel"
        )
    }
}
