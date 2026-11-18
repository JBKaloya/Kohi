import SwiftUI

/// Next to Scan: turns every card between its Kohi face and the pack. Same
/// switch the coffees bar used to carry, as a card that flips.
struct FaceSwitchButton: View {
    @Environment(CardLookStore.self) private var looks
    @State private var flips = 0

    static let symbol = "rectangle.portrait.on.rectangle.portrait.angled"

    private var isKohi: Bool { looks.global == .kohi }

    var body: some View {
        CircleButton(
            systemName: Self.symbol,
            accessibilityLabel: Copy.kohiCards
        ) {
            flips += 1
            withAnimation(Motion.snappy) {
                looks.global = isKohi ? .scan : .kohi
            }
        }
        .rotation3DEffect(.degrees(isKohi ? 0 : 180), axis: (x: 0, y: 1, z: 0))
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isKohi ? "On" : "Off")
        .haptic(.tap, trigger: flips)
    }
}
