import Foundation

/// The places a model is allowed to speak, and nowhere else.
///
/// Every one of them sits on top of something deterministic that already
/// works: the OCR parse, the rules engine, the reference base. That is the
/// invariant the whole experimental layer rests on — turning any of these off
/// degrades the answer, it never breaks the app.
nonisolated enum AIFeature: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Reading a bag, a receipt or a water label that the local parse missed.
    case cardVision = "card-vision"
    /// Turning a dictated phrase into fields when the small grammar cannot.
    case fieldExtract = "field-extract"
    /// A variant of a rules-based recipe, offered beneath it, never instead.
    case recipeAdapt = "recipe-adapt"
    /// Questions answered from the curated knowledge base, with citations.
    case ask
    /// Ranked Suggested correction, constrained to the admissible set.
    case suggestedCorrection = "suggested-correction"
    /// Reading a photographed café menu into coffees, from its OCR text.
    case menuExtract = "menu-extract"
    /// Four-level usefulness scale under every model output.
    case aiFeedback = "ai-feedback"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cardVision: "Read labels"
        case .fieldExtract: "Understand dictation"
        case .recipeAdapt: "Suggest recipe variants"
        case .ask: "Answer questions"
        case .suggestedCorrection: "Suggested correction"
        case .menuExtract: "Read café menus"
        case .aiFeedback: "AI feedback"
        }
    }

    /// What is lost when it is off — shown next to the switch, because a
    /// toggle without a consequence is a toggle nobody dares touch.
    var fallback: String {
        switch self {
        case .cardVision: "Labels are read on device only."
        case .fieldExtract: "Dictation still fills the fields it recognises."
        case .recipeAdapt: "Recipes still come from the rules."
        case .ask: "No answers, no citations."
        case .suggestedCorrection: "The rule still proposes one move."
        case .menuExtract: "Menus are still read on device."
        case .aiFeedback: "Usefulness is not recorded."
        }
    }

    /// Whether the master "Experimental AI" switch governs it.
    ///
    /// Reading a label shipped before this section existed and is part of
    /// what the app does; putting it behind a switch that starts off would
    /// quietly remove a working feature. It stays on, and stays individually
    /// refusable. Reading a menu joined it in build 13: a scan reads with the
    /// model by itself, with nothing to opt into.
    var isExperimental: Bool {
        switch self {
        case .cardVision, .menuExtract, .aiFeedback: false
        case .fieldExtract, .recipeAdapt, .ask, .suggestedCorrection: true
        }
    }

    /// The edge function behind it, when there is one.
    var function: String? {
        switch self {
        case .cardVision: "card-vision"
        case .fieldExtract: "field-extract"
        case .recipeAdapt: "recipe-adapt"
        case .ask: "ask"
        case .suggestedCorrection: "suggested-correction"
        case .menuExtract: "field-extract"
        case .aiFeedback: nil
        }
    }
}
