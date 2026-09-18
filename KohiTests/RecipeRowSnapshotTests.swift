import SwiftUI
import Testing
@testable import Kohi

@MainActor
struct RecipeRowSnapshotTests {
    @Test func aLongNameAndALongAttributionStayOnOneSubtitleLine() {
        let recipe = Recipe(
            name: "V60 « Ultimate » for a very long Sunday morning",
            method: .v60,
            dose: 30,
            water: 500,
            temperature: 92,
            attribution: "James Hoffmann, written at length (2019)"
        )
        SnapshotSupport.image(
            of: RecipeRowView(
                recipe: recipe,
                attribution: recipe.attribution
            ) {},
            height: 90,
            named: "long-row"
        )
    }

    @Test func theChosenRecipeInvertsItsMarkAndRule() {
        let recipe = Recipe(
            name: "V60 « Ultimate »",
            method: .v60,
            dose: 30,
            water: 500,
            temperature: 99,
            attribution: "James Hoffmann"
        )
        SnapshotSupport.image(
            of: RecipeRowView(
                recipe: recipe,
                provenance: "From the pros",
                attribution: recipe.attribution,
                isSelected: true
            ) {},
            height: 90,
            named: "selected-row"
        )
    }
}
