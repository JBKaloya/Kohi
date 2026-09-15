import SwiftUI

/// The two halves of the catalogue.
enum CatalogueTab: String, CaseIterable, Identifiable, Sendable {
    case coffees
    case recipes

    var id: String { rawValue }

    var label: String {
        switch self {
        case .coffees: "Coffees"
        case .recipes: "Recipes"
        }
    }
}

/// The level-1 rail: two catalogue labels over a hairline.
struct CatalogueTabs: View {
    @Binding var selection: CatalogueTab

    var body: some View {
        TabRail(tabs: CatalogueTab.allCases, selection: $selection) { $0.label }
            .padding(.horizontal, 26)
    }
}
