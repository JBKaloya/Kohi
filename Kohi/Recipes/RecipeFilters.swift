import Foundation
import SwiftUI

nonisolated enum RoastBand: String, CaseIterable, Identifiable, Sendable {
    case light
    case medium
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .light: "Light"
        case .medium: "Medium"
        case .dark: "Dark"
        }
    }

    func matches(_ level: RoastLevel?) -> Bool {
        switch self {
        case .light: level == .superLight || level == .light || level == .mediumLight
        case .medium: level == .medium
        case .dark: level == .mediumDark || level == .dark
        }
    }
}

nonisolated enum RecipeMineSource: String, CaseIterable, Identifiable, Sendable {
    case fromBrew
    case savedFromReference
    case adapted

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fromBrew: "From a brew"
        case .savedFromReference: "Saved from the pros"
        case .adapted: "Adapted"
        }
    }

    func matches(_ recipe: Recipe) -> Bool {
        switch self {
        case .fromBrew: recipe.source == .express || (recipe.source == .mine && recipe.brewID != nil)
        case .savedFromReference: recipe.source == .reference || recipe.referenceID != nil
        case .adapted: recipe.source == .adapted
        }
    }
}

nonisolated enum RecipeProfileTag: String, CaseIterable, Identifiable, Sendable {
    case fruity, floral, sweet, bright, clean, body

    var id: String { rawValue }

    var label: String { rawValue.capitalized }
}

nonisolated enum DripperChip: String, CaseIterable, Identifiable, Sendable {
    case v60, flat, chemex, aeropress, immersion, espresso

    var id: String { rawValue }

    var label: String {
        switch self {
        case .v60: "V60"
        case .flat: "Flat"
        case .chemex: "Chemex"
        case .aeropress: "AeroPress"
        case .immersion: "Immersion"
        case .espresso: "Espresso"
        }
    }

    var method: BrewMethod {
        switch self {
        case .v60: .v60
        case .flat: .filter
        case .chemex: .filter
        case .aeropress: .aeropress
        case .immersion: .frenchPress
        case .espresso: .espresso
        }
    }
}

struct RecipeFilterState: Equatable {
    var dripper: DripperChip?
    var size: RecipeSize = .cup
    var roast: RoastBand?
    var source: RecipeMineSource?
    var profile: RecipeProfileTag?
    var authorGrinder: String?

    var method: BrewMethod? { dripper?.method }

    var summary: String {
        var parts: [String] = []
        if let dripper { parts.append(dripper.label) }
        if size != .cup { parts.append(size.label) }
        if let roast { parts.append(roast.label) }
        if let profile { parts.append(profile.label) }
        if let authorGrinder { parts.append(authorGrinder) }
        return parts.joined(separator: " · ")
    }

    var isActive: Bool {
        dripper != nil || roast != nil || profile != nil || authorGrinder != nil || source != nil
    }
}

/// Vertical Filters sheet: Dripper · Cup · Roast · Grinder · Profile.
struct RecipeFilterSheet: View {
    @Binding var state: RecipeFilterState
    var grinders: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    block("Dripper") {
                        chips(DripperChip.allCases, label: \.label, selection: $state.dripper)
                    }
                    block("Cup") {
                        chips(RecipeSize.allCases, label: \.label, selection: sizeBinding)
                    }
                    block("Roast") {
                        chips(RoastBand.allCases, label: \.label, selection: $state.roast)
                    }
                    if !grinders.isEmpty {
                        block("Grinder") {
                            ChipRail {
                                ForEach(grinders, id: \.self) { name in
                                    TagChip(text: name, isSelected: state.authorGrinder == name) {
                                        state.authorGrinder = state.authorGrinder == name ? nil : name
                                    }
                                }
                            }
                        }
                    }
                    block("Profile") {
                        chips(RecipeProfileTag.allCases, label: \.label, selection: $state.profile)
                    }
                }
                .padding(.horizontal, 26)
                .padding(.top, 16)
                .padding(.bottom, 44)
            }
            .scrollIndicators(.hidden)
            .background(Palette.paper.ignoresSafeArea())
            .navigationTitle(Copy.filters)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") { state = RecipeFilterState() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.medium)
                }
            }
        }
        .tint(Palette.ink)
    }

    private var sizeBinding: Binding<RecipeSize?> {
        Binding(
            get: { state.size },
            set: { state.size = $0 ?? .cup }
        )
    }

    private func block<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).catalogueLabel()
            content()
        }
    }

    private func chips<Item: Identifiable & Equatable>(
        _ items: [Item],
        label: @escaping (Item) -> String,
        selection: Binding<Item?>
    ) -> some View {
        ChipPicker(items: items, label: label, selection: selection)
    }
}
