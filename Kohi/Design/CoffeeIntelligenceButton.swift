import SwiftUI

/// The AI call to action: a coffee-brown capsule, the cup mark, and the name.
struct CoffeeIntelligenceButton: View {
    var title: String = Copy.coffeeIntelligence
    var subtitle: String? = Copy.readTheCardAgain
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                CoffeeCupIcon(size: 22, color: Palette.paper)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(Typography.tag)
                        .foregroundStyle(Palette.paper)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Palette.paper.opacity(0.78))
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Palette.primary, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
