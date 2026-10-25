import SwiftUI

/// The three halves of the catalogue: two about drinking at home, one about
/// coffee drunk out.
enum CatalogueTab: String, CaseIterable, Identifiable, Sendable {
    /// Raw value kept: only the label changed.
    case coffees
    case recipes
    case tastings

    var id: String { rawValue }

    var label: String {
        switch self {
        case .coffees: Copy.coffeeCollection
        case .recipes: Copy.recipes
        case .tastings: Copy.tastings
        }
    }
}

/// The level-1 rail: catalogue labels over a hairline.
struct CatalogueTabs: View {
    @Binding var selection: CatalogueTab

    var body: some View {
        TabRail(tabs: CatalogueTab.allCases, selection: $selection) { $0.label }
            .padding(.horizontal, 26)
    }
}
