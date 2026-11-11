#if DEBUG
import SwiftUI

/// The fiche's own choice, said out loud instead of a hidden tap to flip.
/// Debug builds only, until the fiche's face is decided.
struct CardLookSwitch: View {
    let card: CoffeeCard
    @Environment(CardLookStore.self) private var looks

    var body: some View {
        if ImageStore.shared.exists(card.id, kind: .flat) {
            ChipRail {
                TagChip(text: "Kohi card", isSelected: looks.resolved(card) == .kohi) {
                    looks.setOverride(.kohi, for: card.id)
                }
                TagChip(text: "Original", isSelected: looks.resolved(card) == .scan) {
                    looks.setOverride(.scan, for: card.id)
                }
            }
        }
    }
}
#endif
