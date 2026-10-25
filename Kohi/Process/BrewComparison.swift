import Foundation

nonisolated struct ParameterDelta: Equatable, Sendable, Identifiable {
    var id: String { label }
    var label: String
    var a: String
    var b: String
    var delta: String
    var changed: Bool
}

nonisolated struct BrewComparison: Equatable, Sendable {
    let a: Brew
    let b: Brew
    var parameterDeltas: [ParameterDelta]
    var tasteDeltas: [TasteAxis: Int]
    var common: [FlavorTag]
    var onlyA: [FlavorTag]
    var onlyB: [FlavorTag]
    var sentence: String?
    var evidence: Evidence

    static func of(
        _ a: Brew,
        against b: Brew,
        waters: [WaterProfile] = [],
        equipment: [Equipment] = [],
        filterStock: [FilterStock] = []
    ) -> BrewComparison {
        let parameters = parameterDeltas(a, b, waters: waters, equipment: equipment, filterStock: filterStock)
        let taste = tasteDeltas(a, b)
        let (common, onlyA, onlyB) = flavorSplit(a, b)
        let sentence = sentence(parameters: parameters, taste: taste, waters: waters)
        return BrewComparison(
            a: a,
            b: b,
            parameterDeltas: parameters,
            tasteDeltas: taste,
            common: common,
            onlyA: onlyA,
            onlyB: onlyB,
            sentence: sentence,
            evidence: .practice
        )
    }

    private static func parameterDeltas(
        _ a: Brew,
        _ b: Brew,
        waters: [WaterProfile],
        equipment: [Equipment],
        filterStock: [FilterStock]
    ) -> [ParameterDelta] {
        func row(_ label: String, _ left: String?, _ right: String?) -> ParameterDelta? {
            let a = left ?? "—"
            let b = right ?? "—"
            guard a != "—" || b != "—" else { return nil }
            return ParameterDelta(label: label, a: a, b: b, delta: "—", changed: a != b)
        }

        var rows: [ParameterDelta] = []
        if let dose = numeric("Dose", a.dose, b.dose, unit: "g") { rows.append(dose) }
        let aOut = a.water ?? a.beverage
        let bOut = b.water ?? b.beverage
        if let output = numeric("Output", aOut, bOut, unit: "g") { rows.append(output) }
        if let ratio = row("Ratio", a.ratio, b.ratio) {
            var r = ratio
            r.delta = a.ratio == b.ratio ? "—" : (b.ratio ?? "—")
            rows.append(r)
        }
        if let temp = numeric("Temp", a.temperature, b.temperature, unit: "°C") { rows.append(temp) }
        if let time = numeric("Time", a.seconds.map(Double.init), b.seconds.map(Double.init), unit: "s") {
            rows.append(time)
        }
        rows.append(grindDelta(a, b, equipment: equipment))
        if let tds = numeric("TDS", a.tds, b.tds, unit: "%") { rows.append(tds) }
        if let ey = numeric("EY", a.extractionYield, b.extractionYield, unit: "%") { rows.append(ey) }
        if let flow = numeric("Flow", a.averageFlow, b.averageFlow, unit: "g/s") { rows.append(flow) }
        if let agitation = row("Agitation", a.agitation?.label, b.agitation?.label) {
            rows.append(agitation)
        }
        let aWater = waters.first { $0.id == a.waterProfileID }?.displayName
        let bWater = waters.first { $0.id == b.waterProfileID }?.displayName
        if let water = row("Water", aWater, bWater) { rows.append(water) }
        let aFilter = filterStock.first { $0.id == a.filterStockId }?.displayName
        let bFilter = filterStock.first { $0.id == b.filterStockId }?.displayName
        if let filter = row("Filter", aFilter, bFilter) { rows.append(filter) }
        return rows.filter { $0.a != "—" || $0.b != "—" }
    }

    private static func grindDelta(_ a: Brew, _ b: Brew, equipment: [Equipment]) -> ParameterDelta {
        let aText = a.grind.display()
        let bText = b.grind.display()
        let sameGrinder = a.grind.grinderId != nil && a.grind.grinderId == b.grind.grinderId
        let delta: String
        if let av = a.grind.value, let bv = b.grind.value, sameGrinder {
            let d = bv - av
            delta = d == 0 ? "—" : "\(d > 0 ? "+" : "−")\(GrindRange.number(abs(d))) clicks"
        } else if let av = a.grind.micronsProxy(grinder: equipment.first { $0.id == a.grind.grinderId }, calibrations: [], method: a.method),
                  let bv = b.grind.micronsProxy(grinder: equipment.first { $0.id == b.grind.grinderId }, calibrations: [], method: b.method)
        {
            let d = bv - av
            delta = d == 0 ? "—" : "≈ \(d > 0 ? "+" : "−")\(GrindRange.number(abs(d))) µm"
        } else {
            delta = aText == bText ? "—" : "—"
        }
        return ParameterDelta(
            label: "Grind",
            a: aText.isEmpty ? "—" : aText,
            b: bText.isEmpty ? "—" : bText,
            delta: delta,
            changed: aText != bText
        )
    }

    private static func numeric(_ label: String, _ a: Double?, _ b: Double?, unit: String) -> ParameterDelta? {
        guard a != nil || b != nil else { return nil }
        let left = a.map { "\(GrindRange.number($0)) \(unit)" } ?? "—"
        let right = b.map { "\(GrindRange.number($0)) \(unit)" } ?? "—"
        let delta: String
        if let a, let b, a != b {
            let d = b - a
            delta = "\(d > 0 ? "+" : "−")\(GrindRange.number(abs(d))) \(unit)"
        } else {
            delta = "—"
        }
        return ParameterDelta(label: label, a: left, b: right, delta: delta, changed: a != b)
    }

    private static func tasteDeltas(_ a: Brew, _ b: Brew) -> [TasteAxis: Int] {
        var result: [TasteAxis: Int] = [:]
        for axis in TasteAxis.allCases {
            if let av = a.taste[axis], let bv = b.taste[axis] {
                result[axis] = bv - av
            }
        }
        return result
    }

    private static func flavorSplit(_ a: Brew, _ b: Brew) -> ([FlavorTag], [FlavorTag], [FlavorTag]) {
        let aIDs = Set(a.flavors.map(\.id))
        let bIDs = Set(b.flavors.map(\.id))
        let common = a.flavors.filter { bIDs.contains($0.id) }
        let onlyA = a.flavors.filter { !bIDs.contains($0.id) }
        let onlyB = b.flavors.filter { !aIDs.contains($0.id) }
        return (common, onlyA, onlyB)
    }

    private static func sentence(
        parameters: [ParameterDelta],
        taste: [TasteAxis: Int],
        waters: [WaterProfile]
    ) -> String? {
        let changed = parameters.filter(\.changed)
        let effects = taste.filter { abs($0.value) >= 2 }
        let filterWithTime = Set(changed.map(\.label)).subtracting(["Filter", "Time", "Flow"]).isEmpty
            && changed.contains { $0.label == "Filter" }
        if changed.count > 1, !filterWithTime {
            let names = changed.prefix(2).map { $0.label.lowercased() }
            return "Several things changed (\(names.joined(separator: ", "))) — hard to attribute"
        }
        guard let cause = filterWithTime
                ? changed.first(where: { $0.label == "Filter" })
                : changed.first
        else { return nil }
        let effectText = effectPhrase(effects)
        switch cause.label {
        case "Grind":
            if (taste[.acidity] ?? 0) < 0 || (taste[.body] ?? 0) > 0 {
                return "Finer grind (\(cause.delta)) → \(effectText ?? "less acidity, more body")"
            }
            return effectText.map { "Grind \(cause.delta) → \($0)" }
        case "Temp":
            return "Hotter water (\(cause.delta)) → \(effectText ?? "more bitterness")"
        case "Ratio":
            return "Shorter ratio (\(cause.b)) → \(effectText ?? "more body, less clarity")"
        case "Time":
            return "Longer contact (\(cause.delta)) → \(effectText ?? "longer aftertaste")"
        case "Water":
            return "Different water (\(cause.b)) → \(effectText ?? "sweeter, softer")"
        case "Filter":
            let time = parameters.first { $0.label == "Time" }
            let timeBit = time.flatMap { $0.changed ? $0.delta : nil }
            let effect = effectText ?? "more clarity"
            if let timeBit {
                return "Different paper (\(cause.a) → \(cause.b)) → \(timeBit), \(effect)"
            }
            return "Different paper (\(cause.a) → \(cause.b)) → \(effect)"
        default:
            return effectText.map { "\(cause.label) \(cause.delta) → \($0)" }
        }
    }

    private static func effectPhrase(_ effects: [TasteAxis: Int]) -> String? {
        let parts = effects.sorted { $0.key.rawValue < $1.key.rawValue }.map { axis, delta in
            let word = axis.label.lowercased()
            if delta > 0 { return "more \(word)" }
            return "less \(word)"
        }
        guard !parts.isEmpty else { return nil }
        if parts.count == 1 { return parts[0] }
        return parts.dropLast().joined(separator: ", ") + ", " + (parts.last ?? "")
    }
}
