import Foundation

/// The overall score of a cup, in half points: 1 is half a dot, 10 is five.
/// Counted as whole halves so a mean or a comparison is never a float off.
///
/// Builds before half points read and write a whole `rating` from 1 to 5.
/// It is still written beside the halves, rounded down and never below 1,
/// and it decides when the two disagree: that means an older build changed it.
nonisolated enum HalfRating {
    static let range = 1...10

    /// The whole dots an older build shows: 2.5 is 2, 0.5 is 1.
    static func whole(_ halves: Int?) -> Int? {
        guard let halves, range.contains(halves) else { return nil }
        return max(1, halves / 2)
    }

    /// What to keep from a record that carries both. Nil when the whole
    /// score is nil: an older build that cleared it cleared both.
    static func resolve(halves: Int?, whole: Int?) -> Int? {
        guard let whole, (1...5).contains(whole) else { return nil }
        if let halves, range.contains(halves), self.whole(halves) == whole { return halves }
        return whole * 2
    }

    static func points(_ halves: Int) -> Double {
        Double(halves) / 2
    }

    /// "3", "3.5", "0.5".
    static func text(_ halves: Int) -> String {
        halves.isMultiple(of: 2) ? "\(halves / 2)" : "\(halves / 2).5"
    }

    /// Mean in points of the given halves. Nil when there are none.
    static func mean(_ halves: [Int]) -> Double? {
        guard !halves.isEmpty else { return nil }
        return Double(halves.reduce(0, +)) / Double(halves.count * 2)
    }

    /// A mean as shown beside a count: "4.0", "3.5", "2.75". A mean of
    /// halves has at most two decimals, so none are rounded away.
    static func meanText(_ mean: Double) -> String {
        let tenths = (mean * 10).rounded()
        return abs(mean * 10 - tenths) < 0.0001 ? String(format: "%.1f", mean) : String(format: "%.2f", mean)
    }

    /// For VoiceOver: "3.5 out of 5", or "Not rated".
    static func spoken(_ halves: Int?) -> String {
        guard let halves, range.contains(halves) else { return "Not rated" }
        return "\(text(halves)) out of 5"
    }

    /// The rating row's tap: an empty dot gives its whole score, the last
    /// full dot halves, a half dot clears.
    static func tap(_ halves: Int?, dot: Int) -> Int? {
        let whole = dot * 2
        if halves == whole { return whole - 1 }
        if halves == whole - 1 { return nil }
        return whole
    }

    /// Up or down half a point, for VoiceOver. Down from half a dot clears.
    static func step(_ halves: Int?, by delta: Int) -> Int? {
        guard let halves else { return delta > 0 ? range.lowerBound : nil }
        let next = halves + delta
        if next < range.lowerBound { return nil }
        return min(range.upperBound, next)
    }

    /// The score under a finger sliding along the dots: the left half of a
    /// dot is its half point. Never below half a dot; only a tap clears.
    static func slide(x: Double, width: Double) -> Int {
        StepHit.index(x: x, width: width, count: range.upperBound)
    }

    enum Dot: Equatable { case full, half, empty }

    static func dot(_ index: Int, of halves: Int?) -> Dot {
        guard let halves else { return .empty }
        if halves >= index * 2 { return .full }
        if halves == index * 2 - 1 { return .half }
        return .empty
    }
}

/// Which of `count` equal slots a point along a row falls in, 1 to `count`.
/// A finger past either end stays on the first or last slot.
nonisolated enum StepHit {
    static func index(x: Double, width: Double, count: Int) -> Int {
        guard width > 0, count > 0 else { return 1 }
        let slot = Int((x / (width / Double(count))).rounded(.down)) + 1
        return min(count, max(1, slot))
    }
}
