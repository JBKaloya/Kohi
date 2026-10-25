import SwiftUI

enum RecipeTab: String, CaseIterable, Identifiable, Sendable {
    case all
    case mine
    case reference

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: "All"
        case .mine: "My recipes"
        case .reference: "Recipes from the pros"
        }
    }
}

/// Level-2 catalogue labels with a hairline under the active one.
/// Ask has moved to the FAB — it is no longer in the tab rail.
struct RecipeTabs: View {
    @Binding var selection: RecipeTab
    // Kept for call-site compatibility; no longer used.
    var showsAsk: Bool = false
    var onAsk: () -> Void = {}

    var body: some View {
        TabRail(
            tabs: RecipeTab.allCases,
            selection: $selection,
            underline: .active,
            animation: Motion.quick,
            title: { $0.label }
        )
    }
}
