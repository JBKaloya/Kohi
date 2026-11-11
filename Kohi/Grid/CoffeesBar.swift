import SwiftUI

/// Under the tabs and above the grid, outside its scroll view, so it stays
/// put while the cards scroll. The face switch is the first thing on it;
/// filters can join it on the leading side.
struct CoffeesBar: View {
    @Environment(CardLookStore.self) private var looks

    private var kohiCards: Binding<Bool> {
        Binding(
            get: { looks.global == .kohi },
            set: { looks.global = $0 ? .kohi : .scan }
        )
    }

    var body: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            Text(Copy.kohiCards).catalogueLabel()
            LiquidToggle(isOn: kohiCards, label: Copy.kohiCards, height: 24)
        }
        .padding(.horizontal, 26)
        .padding(.top, 10)
        .padding(.bottom, 2)
    }
}
