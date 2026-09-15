import Foundation

/// How a value got into a field, so O4 — "capture without a keyboard" — can be
/// measured rather than asserted.
///
/// Recorded per brew rather than per field: the field-level version is a lot of
/// bookkeeping for a metric, and the dominant path per brew answers the
/// question just as well.
nonisolated enum CaptureSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case typed
    case dictated
    case scanned
    case prefilled

    var id: String { rawValue }

    var label: String {
        switch self {
        case .typed: "Typed"
        case .dictated: "Dictated"
        case .scanned: "Scanned"
        case .prefilled: "Pre-filled"
        }
    }
}

/// What actually happened at a step, against what the recipe asked for.
///
/// Kept beside the recipe's steps rather than overwriting them: the difference
/// between the plan and the execution is the interesting part, and a recipe
/// that silently rewrites itself to match your pour teaches nothing.
nonisolated struct BrewStep: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    /// Where this sat in the recipe, so a real step can be matched to a plan.
    var index: Int
    var action: StepAction
    /// When the step was actually started, in seconds from the start.
    var at: Int
    /// The mass in the vessel when the step ended, if the scale was read.
    var mass: Double?
    /// What the recipe asked for at this step, kept for the comparison.
    var targetAt: Int?
    var targetMass: Double?
    var note: String

    init(
        id: UUID = UUID(),
        index: Int = 0,
        action: StepAction = .pour,
        at: Int = 0,
        mass: Double? = nil,
        targetAt: Int? = nil,
        targetMass: Double? = nil,
        note: String = ""
    ) {
        self.id = id
        self.index = index
        self.action = action
        self.at = at
        self.mass = mass
        self.targetAt = targetAt
        self.targetMass = targetMass
        self.note = note
    }

    var timeLabel: String {
        String(format: "%d:%02d", at / 60, at % 60)
    }

    var actionLabel: String {
        if action == .custom {
            let trimmed = note.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? "Step" : trimmed
        }
        return action.label
    }

    /// "+4 s" against the plan, or nothing when there was no plan.
    var timingDelta: String? {
        guard let targetAt else { return nil }
        let delta = at - targetAt
        guard delta != 0 else { return "on time" }
        return delta > 0 ? "+\(delta) s" : "\(delta) s"
    }
}

nonisolated extension BrewStep {
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        index = try c.decodeIfPresent(Int.self, forKey: .index) ?? 0
        action = try c.decodeIfPresent(StepAction.self, forKey: .action) ?? .pour
        at = try c.decodeIfPresent(Int.self, forKey: .at) ?? 0
        mass = try c.decodeIfPresent(Double.self, forKey: .mass)
        targetAt = try c.decodeIfPresent(Int.self, forKey: .targetAt)
        targetMass = try c.decodeIfPresent(Double.self, forKey: .targetMass)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
    }
}
