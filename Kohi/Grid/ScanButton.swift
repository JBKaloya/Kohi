import SwiftUI

private struct GlassCircleModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.regular, in: .circle)
        } else {
            content
                .background(.ultraThinMaterial, in: Circle())
                .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
        }
    }
}

/// The circular glass button that sits at the bottom of the catalogue.
/// Coffees uses it to scan; Recipes uses it to start a brew.
struct CircleButton: View {
    let systemName: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(Palette.ink)
                .frame(width: 62, height: 62)
        }
        .buttonStyle(PressStyle(scale: Motion.Chrome.buttonPressScale))
        .modifier(GlassCircleModifier())
        .contentShape(.rect(cornerRadius: 31).inset(by: -20))
        .accessibilityLabel(accessibilityLabel)
    }
}

/// The single affordance on the coffee grid. Everything else on that side of
/// the catalogue is reached through a card.
struct ScanButton: View {
    let action: () -> Void

    var body: some View {
        CircleButton(
            systemName: "viewfinder",
            accessibilityLabel: "Scan a card",
            action: action
        )
    }
}
