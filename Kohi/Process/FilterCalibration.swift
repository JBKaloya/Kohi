import Foundation

/// Median drawdown delta between two papers on the same setup.
///
/// Needs three or more brews across two filters, equal grind value, same
/// brewer, dose within a gram. The catalogue `flowClass` is never rewritten.
nonisolated enum FilterCalibration {
    struct Result: Equatable, Sendable {
        var fasterId: UUID
        var slowerId: UUID
        var fasterName: String
        var slowerName: String
        var medianDelta: Double
        var brewCount: Int

        var sentence: String {
            let seconds = GrindRange.number(abs(medianDelta))
            let direction = medianDelta < 0 ? "faster" : "slower"
            return "On your setup: \(seconds) s \(direction) than \(slowerName) (\(brewCount) brews)"
        }
    }

    static func of(
        _ brews: [Brew],
        stock: [FilterStock],
        focusing filterId: UUID
    ) -> Result? {
        let named = Dictionary(uniqueKeysWithValues: stock.map { ($0.id, $0) })
        let usable = brews.filter {
            $0.filterStockId != nil
                && $0.seconds != nil
                && $0.grind.value != nil
                && $0.dose != nil
                && !$0.equipmentIDs.isEmpty
        }
        let others = Set(usable.compactMap(\.filterStockId)).subtracting([filterId])
        var best: Result?
        for other in others {
            guard let result = pair(
                usable,
                a: filterId,
                b: other,
                named: named
            ) else { continue }
            if best == nil || result.brewCount > best!.brewCount {
                best = result
            }
        }
        return best
    }

    private static func pair(
        _ brews: [Brew],
        a: UUID,
        b: UUID,
        named: [UUID: FilterStock]
    ) -> Result? {
        let left = brews.filter { $0.filterStockId == a }
        let right = brews.filter { $0.filterStockId == b }
        var used: Set<UUID> = []
        var deltas: [Double] = []
        for one in left {
            let matches = right.filter { peer in
                peer.grind.value == one.grind.value
                    && Set(peer.equipmentIDs) == Set(one.equipmentIDs)
                    && abs((peer.dose ?? 0) - (one.dose ?? 0)) <= 1
            }
            for peer in matches {
                guard let as_ = one.seconds, let bs = peer.seconds else { continue }
                deltas.append(Double(as_ - bs))
                used.insert(one.id)
                used.insert(peer.id)
            }
        }
        guard deltas.count >= 3,
              let nameA = named[a]?.displayName,
              let nameB = named[b]?.displayName
        else { return nil }
        let sorted = deltas.sorted()
        let median = sorted[sorted.count / 2]
        let count = used.count
        if median <= 0 {
            return Result(
                fasterId: a,
                slowerId: b,
                fasterName: nameA,
                slowerName: nameB,
                medianDelta: median,
                brewCount: count
            )
        }
        return Result(
            fasterId: b,
            slowerId: a,
            fasterName: nameB,
            slowerName: nameA,
            medianDelta: -median,
            brewCount: count
        )
    }
}