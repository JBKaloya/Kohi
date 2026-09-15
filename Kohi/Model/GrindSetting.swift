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

    init(grinderId: UUID? = nil, value: Double? = nil, raw: String? = nil) {
        self.grinderId = grinderId
        self.value = value
        self.raw = raw
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

nonisolated extension GrindSetting {
    enum CodingKeys: String, CodingKey {
        case grinderId, value, raw
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
        if value == nil, let raw {
            value = Self.parse(raw)?.value
        }
        self.init(grinderId: grinderId, value: value, raw: raw)
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
