import Foundation

/// Grams, sticks or drops for a target ppm. Arithmetic only.
nonisolated enum MineralCalculator {
    struct Product: Equatable, Sendable, Decodable {
        var id: String
        var aliases: [String]
        var name: String
        var unit: String
        var divisible: Bool
        var unitBasisLiters: Double
        var nominalPpm: Double?
        var alkalinityPpm: Double?
        var sourceLabel: String
        var verified: Bool

        private enum CodingKeys: String, CodingKey {
            case id, aliases, name, unit, divisible, unitBasisLiters, nominalPpm, alkalinityPpm, sourceLabel, status
        }

        init(id: String, aliases: [String], name: String, unit: String, divisible: Bool, unitBasisLiters: Double, nominalPpm: Double?, alkalinityPpm: Double?, sourceLabel: String, verified: Bool) {
            self.id = id
            self.aliases = aliases
            self.name = name
            self.unit = unit
            self.divisible = divisible
            self.unitBasisLiters = unitBasisLiters
            self.nominalPpm = nominalPpm
            self.alkalinityPpm = alkalinityPpm
            self.sourceLabel = sourceLabel
            self.verified = verified
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            aliases = try c.decodeIfPresent([String].self, forKey: .aliases) ?? []
            name = try c.decode(String.self, forKey: .name)
            unit = try c.decode(String.self, forKey: .unit)
            divisible = try c.decode(Bool.self, forKey: .divisible)
            unitBasisLiters = try c.decode(Double.self, forKey: .unitBasisLiters)
            nominalPpm = try c.decodeIfPresent(Double.self, forKey: .nominalPpm)
            alkalinityPpm = try c.decodeIfPresent(Double.self, forKey: .alkalinityPpm)
            sourceLabel = try c.decode(String.self, forKey: .sourceLabel)
            verified = (try c.decodeIfPresent(String.self, forKey: .status)) == "verified"
        }
    }

    struct Advice: Equatable, Sendable {
        var line: String
        var tds: Double
        var alkalinity: Double?
        var provenance: String
    }

    /// Seeded from docs/mineral-products-seed.csv. Unverified rows stay so a
    /// profile can say the composition is not on file, and never get a number.
    static let products: [Product] = {
        let loaded = load()
        return loaded.isEmpty ? fallback : loaded
    }()

    private static let fallback: [Product] = [
        Product(id: "tww-classic-1gal", aliases: ["tww-classic"], name: "Third Wave Water Classic", unit: "stick", divisible: false, unitBasisLiters: 3.785, nominalPpm: 150, alkalinityPpm: 40, sourceLabel: "Third Wave Water", verified: true)
    ]

    private static func load() -> [Product] {
        guard let url = Bundle.main.url(forResource: "mineral-calculator", withExtension: "json") else {
            return []
        }
        return (try? JSONDecoder().decode([Product].self, from: Data(contentsOf: url))) ?? []
    }

    static func product(id: String) -> Product? {
        products.first { $0.id == id || $0.aliases.contains(id) }
    }

    static func advise(productID: String, targetPpm: Double) -> Advice? {
        guard let product = product(id: productID), product.verified,
              let nominal = product.nominalPpm, nominal > 0, targetPpm > 0
        else { return nil }
        let provenance = "from \(product.sourceLabel) · ≈"
        if !product.divisible, targetPpm < nominal - 0.5 {
            let parts = max(Int((nominal / targetPpm).rounded()) - 1, 1)
            let liters = GrindRange.number(product.unitBasisLiters)
            return Advice(
                line: "Make \(liters) L at \(GrindRange.number(nominal)) ppm with a full \(product.unit), then mix 1 part with \(parts) parts pure water",
                tds: targetPpm,
                alkalinity: product.alkalinityPpm.map { $0 * targetPpm / nominal },
                provenance: provenance
            )
        }
        if product.divisible {
            let perLiter = targetPpm / nominal
            return Advice(
                line: "≈ \(GrindRange.number(perLiter)) \(product.unit) / L",
                tds: targetPpm,
                alkalinity: product.alkalinityPpm.map { $0 * perLiter },
                provenance: provenance
            )
        }
        return Advice(
            line: "1 \(product.unit) / \(GrindRange.number(product.unitBasisLiters)) L",
            tds: nominal,
            alkalinity: product.alkalinityPpm,
            provenance: provenance
        )
    }
}
