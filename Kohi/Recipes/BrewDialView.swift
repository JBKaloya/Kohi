import SwiftUI

/// Dose and water for this cup. Temperature, grind, and equipment stay on the
/// recipe and the kit; they are not edited here.
struct BrewDialView: View {
    @Bindable var session: BrewSession
    var onBack: () -> Void
    var onClose: () -> Void
    var onBrewNow: () -> Void
    var onAlreadyBrewed: () -> Void

    @Environment(SetupStore.self) private var setup

    var body: some View {
        StepFlow(
            step: session.progressIndex,
            total: session.progressTotal,
            question: Copy.howMuch,
            onBack: onBack,
            onClose: onClose,
            primaryTitle: "Brew",
            onPrimary: onBrewNow,
            secondaryTitle: Copy.logWithoutTimer,
            onSecondary: onAlreadyBrewed
        ) {
            VStack(alignment: .leading, spacing: 22) {
                if let applied = session.lastApplication {
                    AppliedFromLastBlock(
                        change: applied.change,
                        onKeep: { session.keepLastApplication() },
                        onUndo: { session.undoLastApplication() }
                    )
                }
                if let source = sourceLine {
                    Text(source)
                        .font(Typography.tag)
                        .foregroundStyle(Palette.inkMuted)
                }
                parameters
            }
            .padding(.bottom, 24)
        }
        .onAppear {
            BrewPrefill.ensureMatchingBrewer(on: &session.brew, setup: setup)
        }
    }

    private var sourceLine: String? {
        let name = (session.recipe?.name ?? session.brew.recipeName)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let name, !name.isEmpty { return name }
        return session.brew.method?.label
    }

    private var parameters: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let note = scaleNote {
                Text(note)
                    .font(Typography.tag)
                    .foregroundStyle(Palette.inkMuted)
                if let scale = session.brew.waterScale, scale != 1,
                   RecipeScaling.factorBounds.contains(scale) {
                    Button("Reset") {
                        if let nominal = session.nominalRecipe {
                            session.brew.dose = nominal.dose
                            session.brew.water = nominal.water
                            session.brew.beverage = nominal.beverage
                            session.resizeRecipeToBrew()
                        }
                    }
                    .catalogueLabel()
                }
            }

            HStack(spacing: 0) {
                NumberRow(
                    Copy.coffeeDose,
                    value: doseBinding,
                    unit: "g",
                    placeholder: Placeholders.text(.brewDose),
                    presence: .useful,
                    compactWidth: 70
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                DerivedValue(text: session.brew.ratio ?? "—")
                    .frame(maxWidth: .infinity)

                NumberRow(
                    session.brew.method == .espresso ? Copy.beverage : Copy.waterWeight,
                    value: waterBinding,
                    unit: "g",
                    placeholder: session.brew.method == .espresso
                        ? Placeholders.text(.brewBeverage)
                        : Placeholders.text(.brewWater),
                    presence: .useful,
                    compactWidth: 70
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let label = rescaledLabel {
                Text(label)
                    .font(Typography.tag)
                    .foregroundStyle(Palette.inkMuted)
            }

            if let cups = RecipeScaling.cupEstimateLabel(for: session.brew.water ?? session.brew.beverage) {
                Text(cups).catalogueLabel()
            }
        }
    }

    private var scaleNote: String? {
        guard let nominal = session.nominalRecipeLiquid,
              let live = RecipeScaling.liquid(of: session.brew),
              abs(live - nominal) > 1
        else { return nil }
        let factor = live / nominal
        if !RecipeScaling.factorBounds.contains(factor) {
            return Copy.tooFarFromRecipe
        }
        return "Scaled from \(GrindRange.number(nominal)) g → \(GrindRange.number(live)) g"
    }

    /// Dose binding. The dose alone does not resize the sequence: the step
    /// masses follow the water, not the coffee.
    private var doseBinding: Binding<Double?> {
        Binding(
            get: { session.brew.dose },
            set: { newDose in
                session.brew.dose = newDose
                session.brew.captureSource = .typed
            }
        )
    }

    /// Water (or beverage out, on espresso). Writing it resizes the attached
    /// recipe through `BrewSession`, which owns the nominal baseline.
    private var waterBinding: Binding<Double?> {
        if session.brew.method == .espresso {
            return Binding(
                get: { session.brew.beverage },
                set: { newVal in
                    session.brew.beverage = newVal
                    session.brew.captureSource = .typed
                    session.resizeRecipeToBrew()
                }
            )
        }
        return Binding(
            get: { session.brew.water },
            set: { newVal in
                session.brew.water = newVal
                session.brew.captureSource = .typed
                session.resizeRecipeToBrew()
            }
        )
    }

    /// Confirmation line, shown only when the sequence actually moved off the
    /// recipe as written.
    private var rescaledLabel: String? {
        guard session.recipe != nil,
              let nominal = session.nominalRecipeLiquid,
              let live = RecipeScaling.liquid(of: session.brew),
              abs(live - nominal) > 1
        else { return nil }
        return "Steps rescaled to \(GrindRange.number(live)) g"
    }
}
