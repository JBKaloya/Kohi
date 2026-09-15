import SwiftUI

enum RecipeTab: String, CaseIterable, Identifiable, Sendable {
    case mine
    case suggested
    case reference

    var id: String { rawValue }

    var label: String {
        switch self {
        case .mine: "Mine"
        case .suggested: "Suggested"
        case .reference: Copy.fromThePros
        }
    }
}

/// Level-2 catalogue labels with a hairline under the active one, Ask on the right.
struct RecipeTabs: View {
    @Binding var selection: RecipeTab
    var showsAsk: Bool
    var onAsk: () -> Void

    var body: some View {
        TabRail(
            tabs: RecipeTab.allCases,
            selection: $selection,
            underline: .active,
            animation: Motion.quick,
            title: { $0.label }
        ) {
            if showsAsk {
                Button(action: onAsk) {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Ask")
                            .font(Typography.label)
                            .tracking(Typography.labelTracking)
                            .textCase(.uppercase)
                    }
                    .foregroundStyle(Palette.inkMuted)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
