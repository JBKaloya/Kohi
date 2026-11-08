import Foundation

/// Where a rolling counter is allowed to sit, and how it steps.
/// Every numeric field in the app picks one of these rather than inventing bounds.
struct NumberRange: Equatable, Sendable {
    var min: Double
    var max: Double
    var step: Double
    var decimals: Int
    /// Where the first tap starts when the value is still empty.
    var `default`: Double

    /// Columns the strip has to be able to show, including the decimal digits.
    var places: Int {
        let scale = pow(10, Double(decimals))
        let scaled = Int((max * scale).rounded())
        return Swift.max(decimals + 1, String(abs(scaled)).count)
    }

    func clamp(_ raw: Double) -> Double {
        let snapped = (raw / step).rounded() * step
        let bounded = Swift.min(max, Swift.max(min, snapped))
        let scale = pow(10, Double(decimals))
        return (bounded * scale).rounded() / scale
    }

    static let dose = NumberRange(min: 1, max: 80, step: 0.1, decimals: 1, default: 15)
    static let water = NumberRange(min: 10, max: 1500, step: 1, decimals: 0, default: 250)
    static let beverage = NumberRange(min: 5, max: 150, step: 1, decimals: 0, default: 36)
    static let temperature = NumberRange(min: 70, max: 100, step: 1, decimals: 0, default: 93)
    static let brewTime = NumberRange(min: 0, max: 600, step: 1, decimals: 0, default: 150)
    static let grindSetting = NumberRange(min: 0, max: 200, step: 0.1, decimals: 1, default: 20)
    static let agtron = NumberRange(min: 0, max: 150, step: 1, decimals: 0, default: 70)
    static let ppm = NumberRange(min: 0, max: 1000, step: 1, decimals: 0, default: 50)
    static let minerals = NumberRange(min: 0, max: 500, step: 1, decimals: 0, default: 0)
    static let burr = NumberRange(min: 20, max: 100, step: 1, decimals: 0, default: 48)
    static let micronsPerStep = NumberRange(min: 0, max: 200, step: 1, decimals: 0, default: 30)
    static let stepsPerTurn = NumberRange(min: 0, max: 200, step: 1, decimals: 0, default: 30)
    static let basket = NumberRange(min: 5, max: 30, step: 1, decimals: 0, default: 18)
    static let pressure = NumberRange(min: 1, max: 15, step: 0.1, decimals: 1, default: 9)
    static let resolution = NumberRange(min: 0.1, max: 1, step: 0.1, decimals: 1, default: 0.1)
    static let price = NumberRange(min: 0, max: 999, step: 1, decimals: 0, default: 0)
    /// A cup at a café: 4.50, 5.20. Ten cents a step.
    static let cupPrice = NumberRange(min: 0, max: 99, step: 0.1, decimals: 2, default: 4)
    static let bagWeight = NumberRange(min: 50, max: 2000, step: 1, decimals: 0, default: 250)
    static let cupping = NumberRange(min: 0, max: 100, step: 0.1, decimals: 1, default: 85)
    static let brewTDS = NumberRange(min: 0, max: 5, step: 0.01, decimals: 2, default: 1.3)
    static let microns = NumberRange(min: 0, max: 2000, step: 1, decimals: 0, default: 400)
}

/// How a held key repeats. The first fire is the caller's; this is everything after.
enum HoldRepeat {
    /// Wait before the first repeat, so a tap stays a tap.
    static let arm: TimeInterval = 0.38

    static func interval(held: TimeInterval) -> TimeInterval {
        held > 0.9 ? 0.055 : 0.09
    }

    /// Ones, then tens once the key has been down for a second and a half.
    static func magnitude(held: TimeInterval) -> Int {
        held > 1.5 ? 10 : 1
    }
}

/// Column counts for a rolling number.
///
/// A column's value is not its digit. It is how many whole units of that
/// place are in the number: 1284 is 1284 for the ones, 128 for the tens,
/// 12 for the hundreds. So 9 → 10 moves the ones column forward one step
/// (9 → 0) and the tens forward one, instead of a strip running backwards.
enum RollMath {
    static func counts(of value: Int, places: Int) -> [Int] {
        guard places > 0 else { return [] }
        return (0..<places).map { place in
            let divisor = Int(pow(10.0, Double(place)))
            return value / max(divisor, 1)
        }
    }

    /// Seconds, least-significant column first.
    /// Bases are 10, 6, 10, 10: the tens of seconds roll over at 6.
    /// 0:59 is `[59, 5, 0, 0]`; 1:00 is `[60, 6, 1, 0]`, so every column
    /// that carries moves forward by one.
    static func clockCounts(seconds: Int) -> (counts: [Int], bases: [Int]) {
        let s = max(0, seconds)
        return ([s, s / 10, s / 60, s / 600], [10, 6, 10, 10])
    }

    static func shownPlaces(scaled: Int, decimals: Int, places: Int) -> Int {
        let digits = max(1, String(abs(scaled)).count)
        return min(places, max(decimals + 1, digits))
    }

    /// Whole turns to skip before the spring runs, when a column is far from home.
    static func jumped(from position: Double, to target: Double, base: Double) -> Double {
        let gap = target - position
        guard abs(gap) > Motion.rollJumpTurns, base > 0 else { return position }
        let sign = gap < 0 ? -1.0 : 1.0
        let turns = ((gap - sign * Motion.rollJumpTurns) / base).rounded()
        return position + turns * base
    }
}

/// The fill behind a slosh handle. The handle itself is written by the finger;
/// this is the liquid catching up, and the wall it bounces off.
struct SloshSim: Equatable, Sendable {
    var value: Double
    var velocity: Double = 0
    var fill: Double
    var fillVelocity: Double = 0
    var held = false
    var viscosity: Double = Motion.Slosh.viscosity
    var momentum: Double = Motion.Slosh.momentum
    var reduced = false

    init(value: Double) {
        self.value = value
        self.fill = value
    }

    mutating func tick(dt raw: Double) {
        let dt = min(max(raw, 0), 2.5)
        if !held, velocity != 0 {
            value += velocity * dt
            let friction = 0.86 + (momentum / 100) * 0.115
            velocity *= pow(friction, dt)
            if value <= 0 || value >= 100 {
                value = min(100, max(0, value))
                velocity = 0
            }
            if abs(velocity) < 0.01 { velocity = 0 }
        }
        let soft = reduced ? 0 : viscosity / 100
        if soft == 0 {
            fill = value
            fillVelocity = 0
        } else {
            let stiff = 0.34 - soft * 0.29
            let damp = 0.74 + soft * 0.22
            fillVelocity += (value - fill) * stiff * dt
            fillVelocity *= pow(damp, dt)
            fill += fillVelocity * dt
            if fill > 100 {
                fill = 100
                fillVelocity = -fillVelocity * Motion.Slosh.wallRestitution
            } else if fill < 0 {
                fill = 0
                fillVelocity = -fillVelocity * Motion.Slosh.wallRestitution
            }
            if abs(value - fill) < 0.02, abs(fillVelocity) < 0.02 {
                fill = value
                fillVelocity = 0
            }
        }
    }

    var atRest: Bool {
        !held && abs(velocity) < 0.01 && abs(fillVelocity) < 0.01 && abs(value - fill) < 0.02
    }

    /// `percent` is 0…100. Taste scores are whole numbers, so the release snaps.
    static func snap(_ percent: Double, steps: Int = 10) -> Int {
        let raw = Int((percent / 100 * Double(steps)).rounded())
        return min(steps, max(0, raw))
    }

    /// Lean of the leading edge, in points. Upright at rest.
    static func lean(fillVelocity: Double, tilt: Double, reduced: Bool) -> Double {
        guard !reduced else { return 0 }
        return min(20, max(-20, (tilt / 100) * fillVelocity * 3))
    }
}
