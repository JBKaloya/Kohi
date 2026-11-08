import Foundation

nonisolated enum ActualSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case timer
    case narration
    case edited
    case none

    var id: String { rawValue }

    var label: String {
        switch self {
        case .timer: "Timer"
        case .narration: "Narration"
        case .edited: "Edited"
        case .none: "Not confirmed"
        }
    }

    var provenance: String {
        switch self {
        case .timer: "From your timer"
        case .narration: "From your timer · narration"
        case .edited: "From what you edited"
        case .none: "Default sequence, not confirmed"
        }
    }
}

nonisolated struct PourRate: Codable, Hashable, Sendable, Identifiable {
    var stepIndex: Int
    var grams: Double
    var seconds: Double
    var gPerS: Double

    var id: Int { stepIndex }

    var band: String {
        if gPerS >= 6 { return "high" }
        if gPerS >= 4 { return "medium" }
        return "low"
    }

    var tag: String {
        "Pour \(stepIndex) · \(GrindRange.number(grams)) g in \(Int(seconds.rounded())) s · \(String(format: "%.1f", gPerS)) g/s · \(band)"
    }
}

nonisolated struct BrewDeviation: Hashable, Sendable, Identifiable {
    var index: Int
    var massDelta: Double?
    var timeDelta: Int?
    var skipped: Bool
    var added: Bool
    var agitationChanged: Bool

    var id: Int { index }

    var isMaterial: Bool {
        if skipped || added || agitationChanged { return true }
        if let massDelta, abs(massDelta) >= 10 { return true }
        if let timeDelta, abs(timeDelta) >= 15 { return true }
        return false
    }
}

nonisolated extension Brew {
    var actualSteps: [BrewStep] {
        get { steps }
        set { steps = newValue }
    }

    /// Title for a brew row: named recipe, else the family, never the brewer.
    var title: String {
        if let recipeName, !recipeName.trimmingCharacters(in: .whitespaces).isEmpty {
            return recipeName
        }
        if let family = method?.family {
            return family.label
        }
        return method?.label ?? "Brew"
    }

    var resolvedAgitation: Agitation? {
        if let agitation { return agitation }
        let fromSteps = (actualSteps + plannedSteps).compactMap(\.agitation).first { $0 != .none }
        return fromSteps
    }

    var deviations: [BrewDeviation] {
        guard !plannedSteps.isEmpty else { return [] }
        var found: [BrewDeviation] = []
        let actual = actualSteps.filter { !$0.skipped || $0.action != .rinse }
        for (index, plan) in plannedSteps.enumerated() {
            let match = actualSteps.first { $0.index == plan.index }
                ?? (index < actualSteps.count ? actualSteps[index] : nil)
            guard let match else {
                found.append(BrewDeviation(index: index, skipped: true, added: false, agitationChanged: false))
                continue
            }
            let massDelta: Double?
            if let planned = plan.targetMass, let real = match.mass {
                massDelta = real - planned
            } else {
                massDelta = nil
            }
            let timeDelta: Int?
            if let planned = plan.targetAt {
                timeDelta = match.at - planned
            } else {
                timeDelta = nil
            }
            found.append(BrewDeviation(
                index: index,
                massDelta: massDelta,
                timeDelta: timeDelta,
                skipped: match.skipped,
                added: false,
                agitationChanged: match.agitation != plan.agitation && (match.agitation != nil || plan.agitation != nil)
            ))
        }
        if actual.count > plannedSteps.count {
            for extra in plannedSteps.count..<actual.count {
                found.append(BrewDeviation(index: extra, skipped: false, added: true, agitationChanged: false))
            }
        }
        return found
    }

    var deviatedFromPlan: Bool {
        deviations.contains(where: \.isMaterial)
    }

    static func rates(from steps: [BrewStep]) -> [PourRate] {
        var rates: [PourRate] = []
        var previousMass = 0.0
        var previousAt = 0
        var pourIndex = 0
        for step in steps.sorted(by: { $0.at < $1.at }) where step.action != .rinse {
            defer {
                if let mass = step.mass { previousMass = mass }
                previousAt = step.at
            }
            guard step.action == .pour || step.action == .bloom || step.action == .shot else { continue }
            guard let mass = step.mass, step.at > previousAt else { continue }
            let poured = mass - previousMass
            guard poured > 0 else { continue }
            pourIndex += 1
            let seconds = Double(step.at - previousAt)
            rates.append(PourRate(
                stepIndex: pourIndex,
                grams: poured,
                seconds: seconds,
                gPerS: poured / seconds
            ))
        }
        return rates
    }

    mutating func refreshPourRates() {
        if actualSource == .none {
            pourRates = []
        } else {
            pourRates = Self.rates(from: actualSteps)
        }
    }
}

nonisolated extension BrewMethod {
    var family: BrewerFamily {
        switch self {
        case .v60, .filter, .aeropress, .frenchPress: .handBrew
        case .espresso, .moka: .espresso
        case .coldBrew: .coldBrew
        }
    }

    /// Which tab a method belongs to in the journey, without its brewer. A
    /// batch brew records `.filter`, so only its brewer says Batch brew.
    var journeyTab: BrewerFamily { family }
}
