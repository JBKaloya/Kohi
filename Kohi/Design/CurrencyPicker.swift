import SwiftUI

/// The one way to pick a currency: chips over `CupPrice.commonCurrencies`.
/// A code outside that list, read off a pack or proposed from where you are,
/// gets a chip of its own in front so it can be seen and kept.
struct CurrencyPicker: View {
    @Binding var code: String?
    /// A card can say nothing about its currency; a tasting always has one.
    var allowsNone = true

    var body: some View {
        FlowLayout {
            ForEach(Self.options(including: code), id: \.self) { option in
                TagChip(text: option, isSelected: code == option) {
                    if code == option {
                        if allowsNone { code = nil }
                    } else {
                        code = option
                    }
                }
            }
        }
    }

    nonisolated static func options(including code: String?) -> [String] {
        let common = CupPrice.commonCurrencies
        guard let code, !code.isEmpty, !common.contains(code) else { return common }
        return [code] + common
    }
}

extension CurrencyPicker {
    /// For a value that is never empty, such as a tasting's currency.
    init(code: Binding<String>) {
        self.init(
            code: Binding<String?>(
                get: { code.wrappedValue },
                set: { if let new = $0 { code.wrappedValue = new } }
            ),
            allowsNone: false
        )
    }
}
