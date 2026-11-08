import SwiftUI

/// The one way to pick a currency: the code in use, which opens
/// `CupPrice.commonCurrencies`. A code outside that list, read off a pack or
/// proposed from where you are, heads the list so it can be seen and kept.
struct CurrencyPicker: View {
    @Binding var code: String?
    /// A card can say nothing about its currency; a tasting always has one.
    var allowsNone = true

    var body: some View {
        Menu {
            ForEach(Self.options(including: code), id: \.self) { option in
                Button {
                    code = option
                } label: {
                    if code == option {
                        Label(option, systemImage: "checkmark")
                    } else {
                        Text(option)
                    }
                }
            }
            if allowsNone {
                Divider()
                Button(Self.noneLabel) { code = nil }
            }
        } label: {
            WellMenuLabel(text: code ?? "—")
                .touchTarget()
        }
        .accessibilityLabel("Currency")
        .accessibilityValue(code ?? Self.noneLabel)
    }

    static let noneLabel = "No currency"

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
