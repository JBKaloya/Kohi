import Foundation

/// Which owned papers a brewer can actually take.
nonisolated enum FilterFit {
    static func compatible(_ stock: FilterStock, with brewer: Equipment) -> Bool {
        if brewer.family == .espresso {
            return stock.resolvedShape == .disc || named(stock.model, fits: brewer)
        }
        let shapes = brewer.resolvedFilterShapes
        let shape = stock.resolvedShape
        if shape == .dedicated || (stock.model?.shape == .dedicated) {
            return named(stock.model, fits: brewer)
        }
        guard !shapes.isEmpty else {
            return named(stock.model, fits: brewer) || stock.modelId == nil
        }
        if let shape, !shapes.contains(shape) {
            if named(stock.model, fits: brewer) {
                return sizeFits(stock, brewer: brewer)
            }
            return false
        }
        if shape == nil, stock.modelId == nil {
            return sizeFits(stock, brewer: brewer) || stock.size.isEmpty
        }
        return sizeFits(stock, brewer: brewer)
    }

    static func named(_ model: FilterModel?, fits brewer: Equipment) -> Bool {
        fitsOverride(model, brewer: brewer)
    }

    @MainActor
    static func owned(for brewer: Equipment, in setup: SetupStore) -> [FilterStock] {
        setup.filterStock
            .filter { compatible($0, with: brewer) }
            .sorted { $0.displayName.localizedCompare($1.displayName) == .orderedAscending }
    }

    @MainActor
    static func `default`(for brewer: Equipment, in setup: SetupStore) -> FilterStock? {
        let owned = owned(for: brewer, in: setup)
        if let marked = owned.first(where: { $0.isDefaultFor.contains(brewer.id) }) {
            return marked
        }
        return owned.first
    }

    private static func sizeFits(_ stock: FilterStock, brewer: Equipment) -> Bool {
        if fitsOverride(stock.model, brewer: brewer) { return true }
        guard let brewerSize = brewer.resolvedSize?.trimmingCharacters(in: .whitespaces),
              !brewerSize.isEmpty
        else { return true }
        let stockSize = stock.size.trimmingCharacters(in: .whitespaces)
        if stockSize.isEmpty { return true }
        if equal(stockSize, brewerSize) { return true }
        if let sizes = stock.model?.sizes, sizes.contains(where: { equal($0, brewerSize) }) {
            return true
        }
        return aliases(brewerSize).contains(where: { equal(stockSize, $0) })
            || aliases(stockSize).contains(where: { equal(brewerSize, $0) })
    }

    private static func fitsOverride(_ model: FilterModel?, brewer: Equipment) -> Bool {
        guard let model else { return false }
        let haystack = (model.fits + [model.model, model.line])
            .joined(separator: " ")
            .lowercased()
        let needles = [brewer.model, brewer.displayName, brewer.size]
            .compactMap { $0?.lowercased() }
            .filter { !$0.isEmpty }
        return needles.contains { haystack.contains($0) }
    }

    private static func equal(_ a: String, _ b: String) -> Bool {
        a.compare(b, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    /// Cafec 4cup ≈ V60 02, Sibarist M ≈ 02, Chemex 6cup ≈ 6 cups.
    private static func aliases(_ size: String) -> [String] {
        switch size.lowercased().replacingOccurrences(of: " ", with: "") {
        case "02", "4cup", "m": return ["02", "4cup", "M"]
        case "01", "1cup", "s": return ["01", "1cup", "S"]
        case "03", "l": return ["03", "L"]
        default: return [size]
        }
    }
}
