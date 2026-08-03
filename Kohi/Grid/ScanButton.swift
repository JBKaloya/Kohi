import SwiftUI

/// The single affordance on the grid. Everything else in the app is reached
/// through a card.
struct ScanButton: View {
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "viewfinder")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(Palette.ink)
                .frame(width: 62, height: 62)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .scaleEffect(isPressed ? Motion.Chrome.buttonPressScale : 1)
        .animation(Motion.quick, value: isPressed)
        .onLongPressGesture(minimumDuration: 0, pressing: { isPressed = $0 }, perform: {})
        .accessibilityLabel("Scan a card")
    }
}
