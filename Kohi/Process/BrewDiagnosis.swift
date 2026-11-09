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
        case rinse
        case filter
        case technique
        case record

        /// Softest first: save what you did, rinse, filter, agitation, temperature, grind, ratio,
        /// time, steps, water, dripper, technique.
        var priority: Int {
            switch self {
            case .record: -1
            case .rinse: 0
            case .filter: 1
            case .agitation: 2
            case .temperature: 3
            case .grind: 4
            case .ratio: 5
            case .time: 6
            case .steps: 7
            case .water: 8
            case .dripper: 9
            case .technique: 10
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
        (candidates(for: brew) + filterMoves(for: brew, brewer: nil, stock: []))
            .min { $0.variable.priority < $1.variable.priority }
    }

    /// Every rule that fires, in no particular order. Exposed for the tests and
    /// for the "why" sheet; the app only ever shows the first by priority.
    static func candidates(
        for brew: Brew,
        tasting: [TastingIntent] = [],
        card: CoffeeCard? = nil
    ) -> [NextTime] {
        var found: [NextTime] = []

        if brew.actualSource == .none, !brew.plannedSteps.isEmpty {
            found.append(NextTime(
                change: Copy.saveWhatYouDid,
                reason: "this brew followed a default sequence",
                variable: .record,
                direction: 0,
                evidence: .unverified
            ))
        }

        if let firstMinute = firstMinuteMove(for: brew, card: card) {
            found.append(firstMinute)
        }

        for rate in brew.pourRates where rate.gPerS >= 6 && brew.bitterness > 0 {
            found.append(NextTime(
                change: "Pour slower (under 6 g/s)",
                reason: "\(rate.tag) is a fast pour",
                variable: .agitation,
                direction: -1,
                evidence: .practice
            ))
        }

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

        found.append(contentsOf: TastingIntent.moves(of: tasting))
        found.append(contentsOf: complexityMoves(for: brew, card: card))

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
    static func admissibleSet(
        for brew: Brew,
        equipment: [Equipment] = [],
        filterStock: [FilterStock] = [],
        tasting: [TastingIntent] = [],
        card: CoffeeCard? = nil
    ) -> [NextTime] {
        var found = candidates(for: brew, tasting: tasting, card: card)
        found.append(contentsOf: stepMoves(for: brew))
        found.append(contentsOf: dripperMoves(for: brew, equipment: equipment))
        let brewer = brew.equipmentIDs.compactMap { id in equipment.first { $0.id == id } }
            .first { $0.kind == .brewer }
        found.append(contentsOf: filterMoves(for: brew, brewer: brewer, stock: filterStock))
        return found
    }

    /// The fast-pour rule, narrowed to the first minute. A washed or
    /// developed coffee goes bitter from early agitation before the grind is
    /// the problem, so the move keeps the grind and slows the start.
    static func firstMinuteMove(for brew: Brew, card: CoffeeCard?) -> NextTime? {
        guard brew.bitterness > 0, let card else { return nil }
        let reading = ExtractionReading.read(brew, card: card)
        guard let flow = reading.firstMinuteFlow, flow >= 6,
              reading.isWashed || reading.isMediumOrDarker else { return nil }
        return NextTime(
            change: "pour slower in the first minute, same grind",
            reason: "bitter after a fast start: \(reading.bitternessChain)",
            variable: .agitation,
            direction: -1,
            evidence: .practice
        )
    }

    /// More complexity is only advised with something to stand on: a measured
    /// extraction below the band, a cup scored low on clarity, or a better
    /// brew of the same coffee that differs in one setting. Otherwise there is
    /// nothing to say, and the screen says so.
    static func complexityMoves(for brew: Brew, card: CoffeeCard?) -> [NextTime] {
        guard brew.complexity == 1 else { return [] }
        var found: [NextTime] = []

        if let yield = brew.extractionYield, yield < 18 {
            found.append(NextTime(
                change: "grind finer",
                reason: "more complexity wanted, and extraction measured at \(GrindRange.number(yield)) %, below the usual band",
                variable: .grind,
                direction: -1,
                evidence: .verified
            ))
        }

        if let clarity = brew.taste.values[.clarity], clarity <= 4, brew.method != .espresso {
            found.append(NextTime(
                change: longerRatio(for: brew),
                reason: "more complexity wanted, and clarity scored \(clarity) of 10 — a longer ratio opens the cup",
                variable: .ratio,
                direction: 1,
                evidence: .partial
            ))
        }

        if let card, let rating = brew.ratingHalves {
            let better = card.brews
                .filter { $0.id != brew.id && ($0.ratingHalves ?? 0) > rating && $0.method == brew.method }
                .max { ($0.ratingHalves ?? 0) < ($1.ratingHalves ?? 0) }
            if let better, let theirs = better.temperature, let ours = brew.temperature, abs(theirs - ours) >= 2 {
                found.append(NextTime(
                    change: theirs > ours ? "hotter water, \(GrindRange.number(theirs)) °C" : "cooler water, \(GrindRange.number(theirs)) °C",
                    reason: "your \(HalfRating.text(better.ratingHalves ?? 0))-dot brew of this coffee ran at \(GrindRange.number(theirs)) °C",
                    variable: .temperature,
                    direction: theirs > ours ? 1 : -1,
                    evidence: .partial
                ))
            } else if let better, let theirs = setting(in: better.grind), let ours = setting(in: brew.grind), theirs != ours {
                found.append(NextTime(
                    change: theirs < ours ? "grind finer" : "grind coarser",
                    reason: "your \(HalfRating.text(better.ratingHalves ?? 0))-dot brew of this coffee ground at \(GrindRange.number(theirs))",
                    variable: .grind,
                    direction: theirs < ours ? -1 : 1,
                    evidence: .partial
                ))
            }
        }
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

    /// Filter and rinse moves. Named papers only appear when the user owns
    /// one of the target class for this brewer.
    static func filterMoves(
        for brew: Brew,
        brewer: Equipment?,
        stock: [FilterStock]
    ) -> [NextTime] {
        var found: [NextTime] = []
        let papery = brew.flavors.contains { tag in
            let hay = (tag.id + " " + tag.displayName).lowercased()
            return hay.contains("papery") || hay.contains("cardboard")
        }
        let rinseStep = brew.steps.first { $0.action == .rinse }
        let rinseUnder: Bool = {
            guard let rinseStep else { return false }
            if rinseStep.skipped { return true }
            guard let target = rinseStep.targetMass, let mass = rinseStep.mass else { return false }
            return mass + 1 < target
        }()
        if papery || rinseUnder {
            let grams = brewer.flatMap { RinseRule.mass(for: stock.first { $0.id == brew.filterStockId }, brewer: $0) }
            let label = grams.map { "Rinse more (\(GrindRange.number($0)) g hot)" } ?? "\(Copy.rinseMore) (150 g hot)"
            found.append(NextTime(
                change: label,
                reason: papery ? "papery or cardboard in the cup" : "the rinse was skipped or short",
                variable: .rinse,
                direction: 1,
                evidence: .practice
            ))
        }

        guard let brewer else { return found }
        let owned = stock.filter { FilterFit.compatible($0, with: brewer) }
        let current = brew.filterStockId.flatMap { id in owned.first { $0.id == id } }
        let currentRank = current?.model?.flowClass?.rank
        let target = brew.recipeSnapshot?.seconds ?? brew.seconds
        let drawdown = brew.seconds

        if let drawdown, let target, target > 0,
           Double(drawdown) > Double(target) * 1.25,
           brew.bitterness > 0,
           let faster = owned
            .filter({ ($0.model?.flowClass?.rank ?? 99) < (currentRank ?? 99) })
            .min(by: { ($0.model?.flowClass?.rank ?? 99) < ($1.model?.flowClass?.rank ?? 99) })
        {
            found.append(NextTime(
                change: "\(faster.displayName) — faster paper, same grind: shorter contact",
                reason: "drawdown overshot the recipe and bitterness is high",
                variable: .filter,
                direction: -1,
                evidence: .practice
            ))
        }

        if let drawdown, let target, target > 0,
           Double(drawdown) < Double(target) * 0.75,
           brew.acidity > 0,
           let slower = owned
            .filter({ ($0.model?.flowClass?.rank ?? -1) > (currentRank ?? -1) })
            .max(by: { ($0.model?.flowClass?.rank ?? -1) < ($1.model?.flowClass?.rank ?? -1) })
        {
            found.append(NextTime(
                change: "\(slower.displayName) — slower paper",
                reason: "drawdown finished early and acidity is high",
                variable: .filter,
                direction: 1,
                evidence: .practice
            ))
        }

        let currentIsMesh = current?.isPaper == false
            || current?.resolvedShape == .cloth
            || current?.model?.material == .metal
            || current?.model?.material == .cloth
        let clarity = brew.taste[.clarity] ?? TasteProfile.midDefault
        if currentIsMesh, clarity <= TasteProfile.lowThreshold,
           let paper = owned.first(where: { $0.isPaper })
        {
            found.append(NextTime(
                change: "\(paper.displayName) — paper filter for clarity",
                reason: "metal or cloth lets fines through",
                variable: .filter,
                direction: 0,
                evidence: .practice
            ))
        }

        if brew.body < 0, clarity >= 7,
           let slower = owned
            .filter({ ($0.model?.flowClass?.rank ?? -1) > (currentRank ?? 2) || ($0.model?.thicknessUm ?? 0) > (current?.model?.thicknessUm ?? 0) })
            .max(by: { ($0.model?.flowClass?.rank ?? 0) < ($1.model?.flowClass?.rank ?? 0) })
        {
            found.append(NextTime(
                change: "\(slower.displayName) — slower or thicker paper",
                reason: "clarity is already there; the cup needs more body",
                variable: .filter,
                direction: 1,
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
            filterStockId: brew.filterStockId,
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
        case .agitation, .water, .technique, .steps, .dripper, .rinse, .filter, .record:
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
