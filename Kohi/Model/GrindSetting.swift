import Foundation

/// A grind setting as a number on a named grinder, with a text fallback.
///
/// The number is what makes two brews comparable and what lets conversion
/// and Insights speak in clicks. `raw` is what you typed when there was no
/// grinder, or a verbal setting ("fine") that has no number. `micronsProxy`
/// is never stored: it is derived from a calibration, then the maker step,
/// and always shown with "≈".
nonisolated struct GrindSetting: Codable, Hashable, Sendable {
    var grinderId: UUID?
    var value: Double?
    var raw: String?
    /// 1…7, matching `GrindGrade`. Survives a grinder with no range.
    var position: Int?

    init(grinderId: UUID? = nil, value: Double? = nil, raw: String? = nil, position: Int? = nil) {
        self.grinderId = grinderId
        self.value = value
        self.raw = raw
        self.position = position
    }

    /// Parse a free-text setting: "22 clicks", "2.4", "fine".
    init(raw text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        self.raw = trimmed.isEmpty ? nil : trimmed
        if let parsed = Self.parse(trimmed) {
            self.value = parsed.value
            if self.raw == nil { self.raw = trimmed }
        }
    }

    var isEmpty: Bool {
        value == nil && (raw == nil || raw?.isEmpty == true)
    }

    /// "22 clicks", "2.4", or the raw text. Empty when nothing was set.
    func display(unit: String? = nil) -> String {
        if let value {
            let number = GrindRange.number(value)
            if let unit, !unit.isEmpty { return "\(number) \(unit)" }
            if let raw, raw.contains(where: { $0.isLetter }) { return raw }
            return number
        }
        return raw ?? ""
    }

    /// Particle-size proxy. Calibration for this grinder wins; otherwise
    /// setting × maker microns per step; otherwise nil. Always shown "≈".
    func micronsProxy(
        grinder: Equipment?,
        calibrations: [GrindCalibration],
        method: BrewMethod?
    ) -> Double? {
        guard let value else { return nil }
        if let grinder, let method,
           let match = calibrations.first(where: {
               $0.grinderID == grinder.id && $0.method == method && $0.micronsProxy != nil
           }),
           let microns = match.micronsProxy, match.setting != 0
        {
            return microns * (value / match.setting)
        }
        if let step = grinder?.makerMicronsPerStep, step > 0 {
            return value * step
        }
        return nil
    }

    var micronsLabel: String? {
        nil
    }

    func micronsLabel(
        grinder: Equipment?,
        calibrations: [GrindCalibration],
        method: BrewMethod?
    ) -> String? {
        guard let microns = micronsProxy(
            grinder: grinder,
            calibrations: calibrations,
            method: method
        ) else { return nil }
        return "≈ \(GrindRange.number(microns)) µm"
    }

    /// Number and a recognised unit, if the text has one.
    struct Parsed: Equatable, Sendable {
        var value: Double
        var unit: String?
    }

    static func parse(_ text: String) -> Parsed? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lowered = trimmed.lowercased()
        let digits = trimmed.drop { !$0.isNumber }
        guard let number = NumberText.parse(String(digits.prefix { $0.isNumber || $0 == "." || $0 == "," }))
        else { return nil }
        let unit: String?
        if lowered.contains("click") || lowered.contains("clic") {
            unit = "clicks"
        } else if lowered.contains("position") {
            unit = "position"
        } else if lowered.contains("#") {
            unit = "number"
        } else {
            unit = nil
        }
        return Parsed(value: number, unit: unit)
    }
}

extension GrindSetting: ExpressibleByStringLiteral {
    init(stringLiteral value: String) {
        self.init(raw: value)
    }
}

/// The seven verbal grades a recipe prints when it has no number. Fine is the
/// left of a grind rail, coarse the right — the same direction as click counts.
nonisolated enum GrindGrade: Int, CaseIterable, Identifiable, Sendable {
    case extraFine
    case fine
    case mediumFine
    case medium
    case mediumCoarse
    case coarse
    case extraCoarse

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .extraFine: "extra-fine"
        case .fine: "fine"
        case .mediumFine: "medium-fine"
        case .medium: "medium"
        case .mediumCoarse: "medium-coarse"
        case .coarse: "coarse"
        case .extraCoarse: "extra-coarse"
        }
    }

    /// 0 is extra-fine, 1 is extra-coarse.
    var position: Double {
        Double(rawValue) / Double(Self.allCases.count - 1)
    }

    static func parse(_ raw: String?) -> GrindGrade? {
        guard let raw else { return nil }
        let key = raw.lowercased().filter { $0.isLetter }
        switch key {
        case "extrafine", "superfine", "espressofine": return .extraFine
        case "fine": return .fine
        case "mediumfine": return .mediumFine
        case "medium": return .medium
        case "mediumcoarse": return .mediumCoarse
        case "coarse": return .coarse
        case "extracoarse", "supercoarse": return .extraCoarse
        default: return nil
        }
    }

    static func nearest(position: Double) -> GrindGrade {
        let scaled = min(max(position, 0), 1) * Double(allCases.count - 1)
        return Self(rawValue: min(max(Int(scaled.rounded()), 0), allCases.count - 1)) ?? .medium
    }

    /// 1…7 notch index.
    var notch: Int { rawValue + 1 }

    static func notch(_ value: Int) -> GrindGrade {
        Self(rawValue: min(max(value, 1), 7) - 1) ?? .medium
    }
}

nonisolated extension GrindSetting {
    /// Writes a 1…7 notch, interpolating clicks when a span is present, never `raw`.
    mutating func setNotch(_ notch: Int, span: GrindSpan?, grinderId: UUID?) {
        let clamped = min(max(notch, 1), 7)
        position = clamped
        raw = nil
        if let span {
            let t = Double(clamped - 1) / 6
            value = span.value(at: t)
            if self.grinderId == nil { self.grinderId = grinderId }
        } else {
            value = nil
        }
    }

    /// Moves the notch from a typed click count.
    mutating func setValue(_ value: Double, span: GrindSpan?, grinderId: UUID?) {
        raw = nil
        self.value = span?.snap(value) ?? value
        if let span {
            position = GrindGrade.nearest(position: span.position(of: self.value ?? value)).notch
        }
        if self.grinderId == nil { self.grinderId = grinderId }
    }

    var resolvedNotch: Int {
        if let position { return min(max(position, 1), 7) }
        if let raw, let grade = GrindGrade.parse(raw) { return grade.notch }
        return GrindGrade.medium.notch
    }
}

/// The numbers a grind rail can travel. Nil means the rail is grades only —
/// a verbal recipe is not invented into clicks until you drag.
nonisolated struct GrindSpan: Equatable, Sendable {
    var low: Double
    var high: Double
    var step: Double
    var unit: String
    var band: ClosedRange<Double>?

    var width: Double { high - low }

    static func stepSize(for grinder: Equipment?) -> Double {
        grinder?.adjustment?.isDetented == true ? 1 : 0.1
    }

    static func make(
        grinder: Equipment?,
        method: BrewMethod?,
        current: Double?
    ) -> GrindSpan? {
        let unit = grinder?.unitLabel ?? ""
        let step = stepSize(for: grinder)
        if let grinder, let method,
           let range = GrindConversion.range(for: method, on: grinder),
           range.span > 0
        {
            let pad = range.span * 0.25
            return GrindSpan(
                low: max(0, range.low - pad),
                high: range.high + pad,
                step: step,
                unit: unit,
                band: range.low...range.high
            )
        }
        if let steps = grinder?.stepsPerRotation, steps > 0 {
            let high = max(Double(steps * 3), current ?? 0)
            return GrindSpan(low: 0, high: high, step: step, unit: unit, band: nil)
        }
        guard let adjustment = grinder?.adjustment else { return nil }
        let floor: Double = switch adjustment {
        case .clicks: 240
        case .stepless, .dial: 10
        }
        return GrindSpan(
            low: 0,
            high: max(floor, current ?? 0),
            step: step,
            unit: unit,
            band: nil
        )
    }

    func snap(_ value: Double) -> Double {
        guard width > 0, step > 0 else { return min(max(value, low), high) }
        let snapped = (value / step).rounded() * step
        return min(max(snapped, low), high)
    }

    func position(of value: Double) -> Double {
        guard width > 0 else { return 0.5 }
        return min(max((value - low) / width, 0), 1)
    }

    func value(at position: Double) -> Double {
        snap(low + min(max(position, 0), 1) * width)
    }
}

    nonisolated extension GrindSetting {
    enum CodingKeys: String, CodingKey {
        case grinderId, value, raw, position
    }

    init(from decoder: any Decoder) throws {
        if let text = try? decoder.singleValueContainer().decode(String.self) {
            self.init(raw: text)
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let grinderId = try c.decodeIfPresent(UUID.self, forKey: .grinderId)
        var value = try c.decodeIfPresent(Double.self, forKey: .value)
        let raw = try c.decodeIfPresent(String.self, forKey: .raw)
        let position = try c.decodeIfPresent(Int.self, forKey: .position)
        if value == nil, let raw {
            value = Self.parse(raw)?.value
        }
        self.init(grinderId: grinderId, value: value, raw: raw, position: position)
    }
}

nonisolated enum Agitation: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case swirl
    case stir
    case wdt
    case pulse

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: "None"
        case .swirl: "Swirl"
        case .stir: "Stir"
        case .wdt: "WDT"
        case .pulse: "Pulse"
        }
    }
}

nonisolated enum Completeness: Equatable, Sendable {
    enum Field: String, CaseIterable, Sendable {
        case method, dose, output, time, grind, rating

        var label: String {
            switch self {
            case .method: "method"
            case .dose: "dose"
            case .output: "output"
            case .time: "time"
            case .grind: "grind"
            case .rating: "rating"
            }
        }
    }

    case complete
    case missing([Field])

    var tag: String {
        switch self {
        case .complete:
            return "Comparable"
        case .missing(let fields):
            if fields == [.rating] { return Copy.addRatingToCompareLater }
            return "missing " + fields.map(\.label).joined(separator: " · ")
        }
    }
}

nonisolated struct BrewFilter: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var brand: String
    var shape: String

    init(id: UUID = UUID(), brand: String = "", shape: String = "") {
        self.id = id
        self.brand = brand
        self.shape = shape
    }

    var displayName: String {
        let parts = [brand, shape]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return parts.joined(separator: " · ")
    }

    var isEmpty: Bool {
        brand.trimmingCharacters(in: .whitespaces).isEmpty
            && shape.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
