import Foundation

/// One change to try next time, with the reason and how sure the reason is.
nonisolated struct NextTime: Hashable, Sendable, Identifiable {
    var id: String { change }

    /// What to do: "grind finer", "ratio 1:15".
    var change: String
    /// Why, in one clause: "probably under-extracted".
    var reason: String
    /// Which variable moves, so the caller can build the draft brew.
    var variable: Variable
    /// The direction, where that means anything: −1 finer or shorter, +1
    /// coarser or longer.
    var direction: Int
    var evidence: Evidence

    nonisolated enum Variable: String, Hashable, Sendable {
        case grind
        case ratio
        case temperature
        case time
        case agitation
        case water
        case steps
        case dripper
        /// Nothing to change in the recipe — the answer is technique.
        case technique

        /// The order the PRD fixes: grind, then ratio, then temperature, then
        /// time, then agitation, then water. A rule further down the list only
        /// fires when nothing above it does.
        var priority: Int {
            switch self {
            case .grind: 0
            case .ratio: 1
            case .temperature: 2
            case .time: 3
            case .agitation: 4
            case .water: 5
            case .steps: 6
            case .dripper: 7
            case .technique: 8
            }
        }
    }
}

/// The diagnostic rules (annexe G7).
///
/// One variable per suggestion, in a fixed order of priority, each carrying its
/// reason and how well established it is. Deterministic, offline, and testable
/// — which is what lets the AI variant sit under it rather than in its place.
nonisolated enum BrewDiagnosis {
    /// The single change to propose for a brew, or nothing when the brew says
    /// nothing. Silence is a valid answer: a coffee you liked and scored
    /// "right" on every axis does not need advice.
    static func nextTime(for brew: Brew) -> NextTime? {
        candidates(for: brew)
            .min { $0.variable.priority < $1.variable.priority }
    }

    /// Every rule that fires, in no particular order. Exposed for the tests and
    /// for the "why" sheet; the app only ever shows the first by priority.
    static func candidates(for brew: Brew) -> [NextTime] {
        var found: [NextTime] = []

        let acidity = brew.acidity
        let bitterness = brew.bitterness
        let body = brew.body

        // Sour and bitter at once is not an extraction level problem: the bed
        // extracted unevenly, and moving the grind makes both worse.
        if acidity > 0, bitterness > 0 {
            found.append(NextTime(
                change: "leave the grind alone; check the water and the distribution",
                reason: "uneven extraction rather than too little of it",
                variable: .technique,
                direction: 0,
                evidence: .partial
            ))
            return found
        }

        // Measured extraction outranks perception: a computed yield is a number,
        // and "too acidic" is a Tuesday.
        if let yield = brew.extractionYield {
            if yield > 22, bitterness > 0 {
                found.append(NextTime(
                    change: "shorten the brew or cool the water",
                    reason: "extraction measured at \(GrindRange.number(yield)) %, above the usual band",
                    variable: .time,
                    direction: -1,
                    evidence: .verified
                ))
            }
            if yield < 18, acidity > 0 {
                found.append(NextTime(
                    change: "grind finer",
                    reason: "extraction measured at \(GrindRange.number(yield)) %, below the usual band",
                    variable: .grind,
                    direction: -1,
                    evidence: .verified
                ))
            }
        }

        // Espresso lives or dies by its shot time, and the window is narrow
        // enough to be a rule rather than a judgement.
        if brew.method == .espresso, let seconds = brew.seconds, seconds > 0 {
            if seconds < 20 {
                found.append(NextTime(
                    change: "grind finer",
                    reason: "\(seconds) s is short for a shot",
                    variable: .grind,
                    direction: -1,
                    evidence: .practice
                ))
            } else if seconds > 35 {
                found.append(NextTime(
                    change: "grind coarser, and distribute before tamping",
                    reason: "\(seconds) s suggests the puck is channelling",
                    variable: .grind,
                    direction: 1,
                    evidence: .partial
                ))
            }
        }

        // Perceived under-extraction: sour without the bitterness that would
        // mean it went too far.
        if acidity > 0, bitterness <= 0 {
            found.append(NextTime(
                change: "grind finer",
                reason: "probably under-extracted",
                variable: .grind,
                direction: -1,
                evidence: .practice
            ))
        }

        if bitterness > 0, acidity <= 0 {
            found.append(NextTime(
                change: "grind coarser",
                reason: "probably over-extracted",
                variable: .grind,
                direction: 1,
                evidence: .practice
            ))
        }

        // Body is about strength, not extraction, so it moves the ratio.
        if body < 0, acidity == 0, bitterness == 0 {
            found.append(NextTime(
                change: shorterRatio(for: brew),
                reason: "thin, but the extraction reads fine — more strength, same extraction",
                variable: .ratio,
                direction: -1,
                evidence: .verified
            ))
        }

        if body > 0 {
            found.append(NextTime(
                change: longerRatio(for: brew),
                reason: "heavy or muddy — less strength, or fewer fines",
                variable: .ratio,
                direction: 1,
                evidence: .practice
            ))
        }

        // Water only comes up when the cup is flat rather than mis-extracted,
        // because changing water changes everything at once.
        if let water = waterRule(for: brew) {
            found.append(water)
        }

        if useFlavorOrigin {
            found.append(contentsOf: originRules(for: brew))
        }

        return found
    }

    /// Every move the model may pick from: G7 candidates, step moves, and a
    /// dripper swap when two drippers are in the kit.
    static func admissibleSet(for brew: Brew, equipment: [Equipment] = []) -> [NextTime] {
        var found = candidates(for: brew)
        found.append(contentsOf: stepMoves(for: brew))
        found.append(contentsOf: dripperMoves(for: brew, equipment: equipment))
        return found
    }

    static func stepMoves(for brew: Brew) -> [NextTime] {
        let steps = brew.recipeSnapshot?.steps ?? brew.steps.map {
            RecipeStep(at: $0.targetAt ?? $0.at, action: $0.action, targetMass: $0.targetMass, note: $0.note)
        }
        var found: [NextTime] = []
        let pours = steps.filter { $0.action == .pour || $0.action == .bloom }
        if pours.count >= 1 {
            found.append(NextTime(
                change: "Add a pour (split the last 100 g)",
                reason: "More agitation, longer contact",
                variable: .steps,
                direction: 1,
                evidence: .practice
            ))
        }
        if steps.contains(where: { $0.action == .bloom }) {
            found.append(NextTime(
                change: "Lengthen the bloom by 15 s",
                reason: "More even wetting before the first pour",
                variable: .steps,
                direction: 1,
                evidence: .practice
            ))
        }
        if pours.count >= 2 {
            found.append(NextTime(
                change: "Stir after pour 2",
                reason: "Most drastic: changes the bed",
                variable: .agitation,
                direction: 1,
                evidence: .practice
            ))
        }
        return found
    }

    /// Clarity wants more bypass; body or sweetness wants less. Needs two drippers.
    static func dripperMoves(for brew: Brew, equipment: [Equipment]) -> [NextTime] {
        let drippers = equipment.filter { $0.kind == .brewer || $0.kind == .espressoMachine }
        guard drippers.count >= 2 else { return [] }

        let ranked = drippers.compactMap { item -> (Equipment, BypassLevel)? in
            let level = item.brewerRef.flatMap { ReferenceBase.brewer(id: $0)?.bypassLevel }
            return level.map { (item, $0) }
        }
        guard ranked.count >= 2 else { return [] }

        let currentID = brew.equipmentIDs.first { id in
            equipment.first { $0.id == id }?.kind == .brewer
        }
        let currentBypass = currentID
            .flatMap { id in equipment.first { $0.id == id } }
            .flatMap { $0.brewerRef.flatMap { ReferenceBase.brewer(id: $0)?.bypassLevel } }

        let sweetness = brew.taste[.sweetness] ?? TasteProfile.midDefault
        let wantsClarity = brew.acidity > 0 || (brew.taste[.clarity] ?? TasteProfile.midDefault) >= 7
        let wantsBody = brew.body < 0 || sweetness <= TasteProfile.lowThreshold

        var found: [NextTime] = []
        if wantsClarity, let next = ranked.max(by: { $0.1.rank < $1.1.rank }),
           next.1.rank > (currentBypass?.rank ?? -1) {
            found.append(NextTime(
                change: "Brew in \(next.0.displayName)",
                reason: "Higher bypass usually reads as more clarity",
                variable: .dripper,
                direction: 1,
                evidence: .practice
            ))
        }
        if wantsBody, let next = ranked.min(by: { $0.1.rank < $1.1.rank }),
           next.1.rank < (currentBypass?.rank ?? 5) {
            found.append(NextTime(
                change: "Brew in \(next.0.displayName)",
                reason: "Lower bypass usually reads as more body",
                variable: .dripper,
                direction: -1,
                evidence: .practice
            ))
        }
        return found
    }

    /// Origin-class rules. Off until the wheel's `origin` field is verified.
    /// Written from Setup on the main actor; diagnosis reads it as a gate.
    nonisolated(unsafe) static var useFlavorOrigin = false

    private static func originRules(for brew: Brew) -> [NextTime] {
        let origins = brew.flavors.compactMap { FlavorWheel.shared.origin(for: $0.id) }
        let dry = origins.filter { $0 == .dryDistillation }.count
        let defect = origins.filter { $0 == .defect }.count
        var found: [NextTime] = []
        if dry >= 2, brew.bitterness > 0 {
            found.append(NextTime(
                change: "Ashy and bitter: shorter contact or cooler water",
                reason: FlavorWheel.shared.originDescription(.dryDistillation) ?? "dry distillation aromas",
                variable: .time,
                direction: -1,
                evidence: .practice
            ))
        }
        if defect >= 2 {
            found.append(NextTime(
                change: "These read like staling: check the roast date",
                reason: FlavorWheel.shared.originDescription(.defect) ?? "defect aromas",
                variable: .technique,
                direction: 0,
                evidence: .practice
            ))
        }
        return found
    }

    /// "ratio 1:15" from wherever the brew currently sits, rounded to
    /// something you would actually weigh out.
    private static func shorterRatio(for brew: Brew) -> String {
        ratioChange(for: brew, by: -1)
    }

    private static func longerRatio(for brew: Brew) -> String {
        ratioChange(for: brew, by: 1)
    }

    private static func ratioChange(for brew: Brew, by delta: Double) -> String {
        guard let dose = brew.dose, dose > 0,
              let liquid = brew.water ?? brew.beverage, liquid > 0
        else { return delta < 0 ? "use a shorter ratio" : "use a longer ratio" }

        let current = liquid / dose
        let target = max(current + delta, 1)
        let mass = (dose * target / 5).rounded() * 5
        return "ratio 1:\(GrindRange.number(target)) — \(GrindRange.number(mass)) g of water"
    }

    /// Water rules from annexe C1: flat and dull points at hardness too low,
    /// muted and lifeless at alkalinity too high. Both need a water profile on
    /// file, since guessing about water you have not measured is fortune
    /// telling.
    private static func waterRule(for brew: Brew) -> NextTime? {
        let sweetness = brew.taste[.sweetness] ?? TasteProfile.midDefault
        let aftertaste = brew.taste[.aftertaste] ?? TasteProfile.midDefault
        guard sweetness <= TasteProfile.lowThreshold || aftertaste <= TasteProfile.lowThreshold else {
            return nil
        }
        return NextTime(
            change: "check the water: hardness around 50–80, alkalinity 30–40 ppm",
            reason: "flat and short, which is more often the water than the grind",
            variable: .water,
            direction: 0,
            evidence: .verified
        )
    }

    // MARK: - Applying it

    /// The draft brew that "Use next time" produces: the same recipe with one
    /// number moved. One variable at a time, which is the whole point.
    static func draft(
        from brew: Brew,
        applying suggestion: NextTime,
        grinder: Equipment? = nil
    ) -> Brew {
        var draft = Brew(
            date: .now,
            method: brew.method,
            dose: brew.dose,
            water: brew.water,
            beverage: brew.beverage,
            grind: brew.grind,
            temperature: brew.temperature,
            recipeID: brew.recipeID,
            recipeRef: brew.recipeRef,
            recipeSnapshot: brew.recipeSnapshot,
            equipmentIDs: brew.equipmentIDs,
            waterProfileID: brew.waterProfileID,
            agitation: brew.agitation,
            filterId: brew.filterId,
            captureSource: .prefilled
        )

        switch suggestion.variable {
        case .grind:
            draft.grind = shiftedGrind(brew.grind, direction: suggestion.direction, grinder: grinder)
        case .ratio:
            if let dose = brew.dose, dose > 0,
               let liquid = brew.water ?? brew.beverage, liquid > 0 {
                let target = max(liquid / dose + Double(suggestion.direction), 1)
                let mass = (dose * target / 5).rounded() * 5
                if brew.water != nil { draft.water = mass } else { draft.beverage = mass }
            }
        case .temperature:
            draft.temperature = brew.temperature.map { $0 + Double(suggestion.direction) * 2 }
        case .time:
            draft.seconds = brew.seconds.map {
                max($0 + suggestion.direction * 10, 5)
            }
        case .agitation, .water, .technique, .steps, .dripper:
            // Nothing numeric to move; the note carries it.
            break
        }

        draft.notes = suggestion.change.capitalizedFirst
        return draft
    }

    /// Moves a numeric grind setting by a notch, and leaves a verbal one alone
    /// — "medium-fine, finer" is a note, not a setting.
    static func shiftedGrind(
        _ grind: GrindSetting,
        direction: Int,
        grinder: Equipment?
    ) -> GrindSetting {
        guard direction != 0 else { return grind }
        guard let value = grind.value ?? setting(in: grind) else { return grind }

        let moved: Double
        if let grinder {
            moved = GrindConversion.settingShift(
                from: value,
                by: 0.06 * Double(direction),
                grinder: grinder
            )
        } else {
            moved = (value + Double(direction)).rounded()
        }
        var next = grind
        next.value = moved
        let unit = grind.raw.map {
            String($0.drop { $0.isNumber || $0 == "." || $0 == "," || $0 == " " })
                .trimmingCharacters(in: .whitespaces)
        } ?? ""
        next.raw = unit.isEmpty
            ? GrindRange.number(moved)
            : "\(GrindRange.number(moved)) \(unit)"
        return next
    }

    // MARK: - Compare

    /// Deltas against a reference brew, in the `tag` vocabulary:
    /// "−2 clicks · +0.5 g · −10 s".
    static func compare(_ brew: Brew, to reference: Brew) -> [String] {
        var parts: [String] = []

        if let mine = brew.dose, let theirs = reference.dose, mine != theirs {
            parts.append(delta(mine - theirs, unit: "g"))
        }
        if let mine = brew.water ?? brew.beverage,
           let theirs = reference.water ?? reference.beverage, mine != theirs {
            parts.append(delta(mine - theirs, unit: "g water"))
        }
        if let mine = brew.temperature, let theirs = reference.temperature, mine != theirs {
            parts.append(delta(mine - theirs, unit: "°C"))
        }
        if let mine = brew.seconds, let theirs = reference.seconds, mine != theirs {
            parts.append(delta(Double(mine - theirs), unit: "s"))
        }
        if let mine = setting(in: brew.grind), let theirs = setting(in: reference.grind),
           mine != theirs {
            parts.append(delta(mine - theirs, unit: "clicks"))
        }
        return parts
    }

    /// The number inside a grind setting, whatever it is written with:
    /// "22 clicks", "3.5", "dial 15". A purely verbal grind has none, and
    /// comparing "medium-fine" to "fine" is not arithmetic.
    static func setting(in grind: GrindSetting) -> Double? {
        if let value = grind.value { return value }
        guard let raw = grind.raw else { return nil }
        return setting(in: raw)
    }

    static func setting(in grind: String) -> Double? {
        let digits = grind.drop { !$0.isNumber }
        return NumberText.parse(String(digits.prefix { $0.isNumber || $0 == "." || $0 == "," }))
    }

    private static func delta(_ value: Double, unit: String) -> String {
        let sign = value > 0 ? "+" : "−"
        return "\(sign)\(GrindRange.number(abs(value))) \(unit)"
    }
}
