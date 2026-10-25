import Foundation

/// What you'd change next time, read off a brew.
///
/// Acidity, bitterness and body are stored as observations (+1 "too
/// acidic"), as they always were, so the rules and every past brew keep their
/// meaning. The rows read as wishes ("less acidity"), so only the display
/// flips. Complexity is new and stored as the wish itself.
nonisolated enum BrewWish {
    enum Axis: String, CaseIterable, Identifiable, Sendable {
        case acidity
        case bitterness
        case body
        case complexity

        var id: String { rawValue }

        var label: String {
            switch self {
            case .acidity: "Acidity"
            case .bitterness: "Bitterness"
            case .body: "Body"
            case .complexity: "Complexity"
            }
        }
    }

    /// −1 less, 0 as is, +1 more.
    static func wish(_ axis: Axis, of brew: Brew) -> Int {
        switch axis {
        case .acidity: -brew.acidity
        case .bitterness: -brew.bitterness
        case .body: -brew.body
        case .complexity: brew.complexity ?? 0
        }
    }

    static func set(_ axis: Axis, wish: Int, on brew: inout Brew) {
        let wish = max(-1, min(1, wish))
        switch axis {
        case .acidity: brew.acidity = -wish
        case .bitterness: brew.bitterness = -wish
        case .body: brew.body = -wish
        case .complexity: brew.complexity = wish == 0 ? nil : wish
        }
    }

    /// "less acidity", "as is", "more complexity".
    static func caption(_ axis: Axis, wish: Int) -> String {
        let name = axis.label.lowercased()
        if wish < 0 { return "less \(name)" }
        if wish > 0 { return "more \(name)" }
        return "as is"
    }

    /// Whether anything was asked for.
    static func hasWish(_ brew: Brew) -> Bool {
        Axis.allCases.contains { wish($0, of: brew) != 0 }
    }
}
