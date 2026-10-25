import Foundation

/// What a brew and its coffee say about extraction, read once and shared by
/// the improve screen, the rules and the model payload.
///
/// Reads steps and rates only. A connected scale would feed the same steps,
/// so nothing here needs to change for it.
nonisolated struct ExtractionReading: Hashable, Sendable, Encodable {
    enum Band: String, Hashable, Sendable, Encodable {
        case low
        case medium
        case high

        /// Same thresholds as a single pour's band.
        init(gPerS: Double) {
            if gPerS >= 6 { self = .high }
            else if gPerS >= 4 { self = .medium }
            else { self = .low }
        }
    }

    // The extraction
    /// Water delivered over the first 60 s, in g/s. Nil without real steps.
    var firstMinuteFlow: Double?
    var agitationBand: Band?
    /// Bloom water over dose.
    var bloomRatio: Double?
    var pours: Int
    var totalSeconds: Int?
    var ratio: String?
    var temperature: Double?
    var grind: String?
    var source: String

    // The coffee
    var process: String?
    var roastLevel: String?
    /// Days between the roast date and the brew.
    var restDays: Int?
    var origin: String?
    var altitude: String?

    var isWashed: Bool {
        guard let process = process?.lowercased() else { return false }
        return process.contains("wash") || process.contains("lavé") || process.contains("lave")
    }

    var isMediumOrDarker: Bool {
        guard let roastLevel, let level = RoastLevel(rawValue: roastLevel) else { return false }
        return [.medium, .mediumDark, .dark].contains(level)
    }

    static func read(_ brew: Brew, card: CoffeeCard?) -> ExtractionReading {
        let real = brew.actualSource != .none
        let steps = real ? brew.actualSteps.sorted { $0.at < $1.at } : []

        let flow = firstMinuteFlow(steps: steps)
        var bloomRatio: Double?
        if let bloom = steps.first(where: { $0.action == .bloom }),
           let mass = bloom.mass, let dose = brew.dose, dose > 0 {
            bloomRatio = mass / dose
        }
        let pours = steps.filter { $0.action == .pour || $0.action == .bloom }.count

        var restDays: Int?
        if let roasted = card?.roastedOn {
            let days = Calendar.current.dateComponents([.day], from: roasted, to: brew.date).day ?? 0
            restDays = max(0, days)
        }

        func text(_ value: String?) -> String? {
            guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
            return value
        }
        let origin = card.map { [$0.region, $0.country].compactMap { text($0) }.joined(separator: ", ") }

        let grind = brew.grind.display()
        return ExtractionReading(
            firstMinuteFlow: flow,
            agitationBand: flow.map(Band.init(gPerS:)),
            bloomRatio: bloomRatio,
            pours: pours,
            totalSeconds: brew.seconds.flatMap { $0 > 0 ? $0 : nil },
            ratio: brew.ratio,
            temperature: brew.temperature,
            grind: grind.isEmpty ? nil : grind,
            source: brew.actualSource.rawValue,
            process: text(card?.process),
            roastLevel: card?.roastLevel?.rawValue,
            restDays: restDays,
            origin: origin.flatMap(text),
            altitude: text(card?.altitude)
        )
    }

    /// The mass in the brewer at the last step within the first minute, over
    /// the time it took. Rinses do not count.
    static func firstMinuteFlow(steps: [BrewStep]) -> Double? {
        let within = steps.filter { $0.action != .rinse && $0.at > 0 && $0.at <= 60 && $0.mass != nil }
        guard let last = within.max(by: { $0.at < $1.at }), let mass = last.mass, mass > 0 else { return nil }
        return mass / Double(last.at)
    }

    struct Factor: Hashable, Sendable, Identifiable {
        var label: String
        var value: String
        var id: String { label }
    }

    var extractionFactors: [Factor] {
        var rows: [Factor] = []
        if let flow = firstMinuteFlow, let band = agitationBand {
            rows.append(Factor(label: "First minute", value: "\(String(format: "%.1f", flow)) g/s · \(band.rawValue)"))
        }
        if pours > 0 {
            var value = pours == 1 ? "1 pour" : "\(pours) pours"
            if let bloomRatio { value += " · bloom \(String(format: "%.1f", bloomRatio))× dose" }
            rows.append(Factor(label: "Pours", value: value))
        }
        if let totalSeconds {
            rows.append(Factor(label: "Time", value: String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)))
        }
        let strength = [ratio, temperature.map { "\(GrindRange.number($0)) °C" }].compactMap { $0 }
        if !strength.isEmpty {
            rows.append(Factor(label: "Ratio", value: strength.joined(separator: " · ")))
        }
        if let grind {
            rows.append(Factor(label: "Grind", value: grind))
        }
        return rows
    }

    var coffeeFactors: [Factor] {
        var rows: [Factor] = []
        if let process { rows.append(Factor(label: "Process", value: process)) }
        if let roastLevel, let level = RoastLevel(rawValue: roastLevel) {
            rows.append(Factor(label: "Roast", value: level.label))
        }
        if let restDays { rows.append(Factor(label: "Rest", value: restDays == 1 ? "1 day off roast" : "\(restDays) days off roast")) }
        let place = [origin, altitude].compactMap { $0 }
        if !place.isEmpty { rows.append(Factor(label: "Origin", value: place.joined(separator: " · "))) }
        return rows
    }

    /// "first minute 7.2 g/s · washed · medium": the chain a reason carries.
    var bitternessChain: String {
        var parts: [String] = []
        if let firstMinuteFlow { parts.append("first minute \(String(format: "%.1f", firstMinuteFlow)) g/s") }
        if isWashed, let process { parts.append(process.lowercased()) }
        if isMediumOrDarker, let roastLevel, let level = RoastLevel(rawValue: roastLevel) {
            parts.append(level.label.lowercased())
        }
        return parts.joined(separator: " · ")
    }
}
