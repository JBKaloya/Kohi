import Foundation

/// What a Live brew becomes once the dictation is read: the steps heard,
/// written onto the brew, and the split they make.
nonisolated enum LiveSteps {
    typealias TimedStep = SpokenBrewParser.TimedStep

    /// The steps heard, or one step for the whole clock when none could be
    /// read. `nothingHeard` tells the screen to say so.
    static func heard(
        from phrases: [VoiceNoteTranscriber.Phrase],
        seconds: Int?,
        water: Double?
    ) -> (steps: [TimedStep], nothingHeard: Bool) {
        let steps = SpokenBrewParser.timedSteps(phrases: phrases)
        guard steps.isEmpty else { return (steps, false) }
        return (fallback(seconds: seconds, water: water), true)
    }

    static func fallback(seconds: Int?, water: Double?) -> [TimedStep] {
        [TimedStep(at: 0, action: .pour, mass: water, until: seconds)]
    }

    /// The heard steps become what was done. A Live brew has no plan, so
    /// there is nothing to compare them with. Water left empty on How much?
    /// is the last mass said.
    static func apply(_ heard: [TimedStep], to brew: inout Brew) {
        brew.plannedSteps = []
        brew.actualSteps = brewSteps(heard)
        brew.actualSource = .narration
        if brew.water == nil, brew.method != .espresso, let last = lastMass(of: heard) {
            brew.water = last
        }
        brew.refreshPourRates()
    }

    static func lastMass(of heard: [TimedStep]) -> Double? {
        heard.last { PourSplit.carriesWater($0.action) && $0.mass != nil }?.mass
    }

    static func brewSteps(_ heard: [TimedStep]) -> [BrewStep] {
        heard.sorted { $0.at < $1.at }.enumerated().map { index, step in
            BrewStep(
                index: index,
                action: step.action,
                at: step.at,
                mass: step.mass,
                targetAt: step.until,
                note: step.note,
                agitation: step.agitation
            )
        }
    }

    static func timed(_ steps: [BrewStep]) -> [TimedStep] {
        steps.map {
            TimedStep(at: $0.at, action: $0.action, mass: $0.mass, agitation: $0.agitation, until: $0.targetAt, note: $0.note)
        }
    }

    static func recipeSteps(_ steps: [BrewStep]) -> [RecipeStep] {
        steps.sorted { $0.at < $1.at }.map {
            RecipeStep(
                at: $0.at,
                action: $0.action,
                targetMass: $0.mass ?? $0.targetMass,
                untilSeconds: $0.targetAt,
                note: $0.note,
                agitation: $0.agitation
            )
        }
    }

    /// The split the dictated masses make, read like the editor reads one.
    static func split(of brew: Brew, countsBloom: Bool) -> PourSplit.Split? {
        let steps = recipeSteps(brew.actualSteps)
        let last = steps.last { PourSplit.carriesWater($0.action) && $0.targetMass != nil }?.targetMass
        guard let total = brew.water ?? last, total > 0 else { return nil }
        return PourSplit.split(steps: steps, total: total, countsBloom: countsBloom)
    }
}
