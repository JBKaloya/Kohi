import Foundation

/// What one cup cost. Separate from a bag's price and its price per kilo.
nonisolated struct CupPrice: Codable, Hashable, Sendable {
    var amount: Decimal
    /// ISO 4217, upper case: "EUR".
    var currency: String

    init(amount: Decimal, currency: String) {
        self.amount = amount
        self.currency = currency.uppercased()
    }

    /// "4,50 €", in the reader's locale.
    var formatted: String {
        amount.formatted(.currency(code: currency))
    }

    /// The reader's currency, falling back to euros.
    static var localCurrency: String {
        Locale.current.currency?.identifier ?? "EUR"
    }

    static let commonCurrencies = ["EUR", "USD", "GBP", "JPY", "CHF", "AUD", "CAD", "SEK", "DKK", "NOK"]
}
