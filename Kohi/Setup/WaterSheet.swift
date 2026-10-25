import SwiftUI

/// A water profile: where it comes from, and what is in it.
///
/// The four ions are what you can read off a bottle label or a water report,
/// so those are what gets typed. Hardness and alkalinity are computed
/// underneath and shown against the SCA band — as a position, not a grade.
struct WaterSheet: View {
    @Environment(SetupStore.self) private var setup
    @Environment(\.dismiss) private var dismiss

    @State private var draft: WaterProfile
    @State private var isNew: Bool
    @State private var isConfirmingDelete = false
    @State private var tapCount = 0
    var onCreated: ((WaterProfile) -> Void)?

    init(profile: WaterProfile?, onCreated: ((WaterProfile) -> Void)? = nil) {
        _draft = State(initialValue: profile ?? WaterProfile())
        _isNew = State(initialValue: profile == nil)
        self.onCreated = onCreated
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    FieldGroup(title: "Water") {
                        TextRow(label: "Name", text: $draft.name, placeholder: Placeholders.text(.waterName), presence: .useful)
                        FormField(label: "Source") {
                            ChipPicker(
                                items: WaterSource.allCases,
                                label: \.label,
                                selection: sourceBinding,
                                allowsDeselect: false,
                                onPick: { tapCount += 1 }
                            )
                        }
                    }

                    if !ReferenceBase.waters.isEmpty, isNew {
                        knownWatersSection
                    }

                    if draft.source == .filtered { filtrationSection }
                    if draft.source == .recipe { recipeBaseSection }

                    mineralsSection
                    readingSection

                    if draft.source == .recipe || draft.mineralProductID != nil || draft.additiveName != nil {
                        additiveSection
                    }

                    notesSection

                    if !isNew {
                        if !draft.isDefault {
                            Button("Make this my default water") {
                                setup.makeDefault(draft)
                                draft.isDefault = true
                                tapCount += 1
                            }
                            .font(Typography.tag)
                            .foregroundStyle(Palette.ink)
                        }
                        Button("Remove this water") { isConfirmingDelete = true }
                            .font(Typography.tag)
                            .foregroundStyle(Palette.inkMuted)
                    }
                }
                .padding(.horizontal, 26)
                .padding(.top, 14)
                .padding(.bottom, 44)
                .fieldKeyboardClearance()
            }
            .scrollIndicators(.hidden)
            .background(Palette.paper.ignoresSafeArea())
            .navigationTitle(isNew ? "Add water" : draft.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).fontWeight(.medium)
                }
            }
        }
        .tint(Palette.ink)
        .haptic(.tap, trigger: tapCount)
        .confirmationDialog(
            "Remove \(draft.displayName)?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                setup.delete(draft)
                dismiss()
            }
        }
    }

    /// `ChipPicker` deals in optionals; the source never is.
    private var sourceBinding: Binding<WaterSource?> {
        Binding(
            get: { draft.source },
            set: { if let value = $0 { draft.source = value } }
        )
    }

    // MARK: - Sections

    private var knownWatersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Known waters")
                .catalogueLabel()
            FlowLayout {
                ForEach(ReferenceBase.waters) { water in
                    TagChip(text: water.name, isSelected: draft.waterRef == water.id) {
                        tapCount += 1
                        withAnimation(Motion.quick) {
                            draft = WaterProfile(
                                id: draft.id,
                                name: water.name,
                                source: .bottled,
                                tds: water.tds,
                                calcium: water.calcium,
                                magnesium: water.magnesium,
                                sodium: water.sodium,
                                bicarbonate: water.bicarbonate,
                                notes: water.note ?? draft.notes,
                                isDefault: draft.isDefault,
                                waterRef: water.id,
                                createdAt: draft.createdAt
                            )
                        }
                    }
                }
            }
            Text("Only waters whose figures were verified against a label are listed.")
                .font(Typography.tag)
                .foregroundStyle(Palette.inkMuted)
        }
    }

    private var mineralsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What's in it")
                .catalogueLabel()
            NumberRow("ppm", value: $draft.tds, unit: "ppm", placeholder: Placeholders.text(.waterTDS))
            NumberRow("Calcium", value: $draft.calcium, unit: "mg/L", placeholder: Placeholders.text(.waterCalcium))
            NumberRow("Magnesium", value: $draft.magnesium, unit: "mg/L", placeholder: Placeholders.text(.waterMagnesium))
            NumberRow("Sodium", value: $draft.sodium, unit: "mg/L", placeholder: Placeholders.text(.waterSodium))
            NumberRow("Bicarbonate", value: $draft.bicarbonate, unit: "mg/L", placeholder: Placeholders.text(.waterBicarbonate))

            Text("""
            Off the bottle label or your water report. Leave blank what you \
            don't know — a blank is honest, a zero is a claim.
            """)
            .font(Typography.tag)
            .foregroundStyle(Palette.inkMuted)
        }
    }

    /// The three bands. Alkalinity below the band is where light-roast filter
    /// brewing deliberately sits, which is why nothing here is marked wrong.
    private var readingSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("How it reads")
                .catalogueLabel()

            TargetRow(
                label: "ppm",
                value: draft.tds,
                range: WaterTarget.tds.range,
                target: WaterTarget.tds.target,
                unit: WaterTarget.tds.unit
            )
            TargetRow(
                label: "Hardness",
                value: draft.generalHardness,
                range: WaterTarget.hardness.range,
                target: WaterTarget.hardness.target,
                unit: WaterTarget.hardness.unit
            )
            TargetRow(
                label: "Alkalinity",
                value: draft.alkalinity,
                range: WaterTarget.alkalinity.range,
                target: WaterTarget.alkalinity.target,
                unit: WaterTarget.alkalinity.unit
            )

            Text("""
            GH ≈ 2.50 × Ca + 4.12 × Mg, KH ≈ 0.82 × HCO₃, both in ppm CaCO₃. \
            The band is the SCA range; sitting outside it is a choice, not a \
            mistake.
            """)
            .font(Typography.tag)
            .foregroundStyle(Palette.inkMuted)
        }
    }

    private var filtrationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Filtered with").catalogueLabel()
            ChipPicker(
                items: FiltrationSystem.allCases,
                label: \.label,
                selection: Binding(
                    get: { draft.filtrationSystem },
                    set: { draft.filtrationSystem = $0 }
                ),
                onPick: { tapCount += 1 }
            )
            if draft.filtrationSystem != nil, draft.tds == nil, draft.calcium == nil {
                Text("No analysis on file for this filter yet")
                    .font(Typography.tag)
                    .foregroundStyle(Palette.inkMuted)
            }
        }
    }

    private var recipeBaseSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Base").catalogueLabel()
            ChipPicker(
                items: WaterBase.allCases,
                label: \.label,
                selection: Binding<WaterBase?>(
                    get: { draft.waterBase ?? .distilled },
                    set: {
                        draft.waterBase = $0
                        if draft.waterBase == .distilled {
                            draft.calcium = 0
                            draft.magnesium = 0
                            draft.sodium = 0
                            draft.bicarbonate = 0
                            draft.tds = 0
                        }
                    }
                ),
                allowsDeselect: false,
                onPick: { tapCount += 1 }
            )
        }
    }

    private var additiveSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Minerals")
                .catalogueLabel()

            FlowLayout {
                ForEach(ReferenceBase.mineralProducts) { product in
                    TagChip(
                        text: product.name,
                        isSelected: draft.mineralProductID == product.id
                    ) {
                        tapCount += 1
                        apply(product)
                    }
                }
            }

            if let id = draft.mineralProductID,
               let advice = MineralCalculator.advise(productID: id, targetPpm: draft.tds ?? MineralCalculator.product(id: id)?.nominalPpm ?? 150) {
                Text(advice.line)
                    .font(Typography.value)
                    .foregroundStyle(Palette.ink)
                Text(advice.provenance)
                    .font(Typography.tag)
                    .foregroundStyle(Palette.inkMuted)
            } else if draft.mineralProductID != nil {
                // Unknown product, or one whose composition is not published:
                // say so and leave the fields below to be filled by hand.
                Text(Copy.compositionNotOnFile)
                    .font(Typography.tag)
                    .foregroundStyle(Palette.inkMuted)
            }

            TextRow(
                label: "Dose",
                text: $draft.additiveDose.orEmpty,
                placeholder: Placeholders.text(.additiveDose),
                capitalization: .sentences
            )
        }
    }

    private func apply(_ product: ReferenceBase.MineralProduct) {
        if draft.mineralProductID == product.id {
            draft.mineralProductID = nil
            draft.additiveName = nil
            draft.additiveDose = nil
            return
        }
        draft.mineralProductID = product.id
        draft.additiveName = product.name
        draft.additiveDose = product.dose
        guard product.compositionOnFile else { return }
        if let tds = product.tds { draft.tds = tds }
        if let calcium = product.calcium { draft.calcium = calcium }
        if let magnesium = product.magnesium { draft.magnesium = magnesium }
        if let sodium = product.sodium { draft.sodium = sodium }
        if let bicarbonate = product.bicarbonate { draft.bicarbonate = bicarbonate }
    }

    private var notesSection: some View {
        FieldGroup(title: "Notes") {
            TextField("", text: $draft.notes, axis: .vertical)
                .formValue()
                .lineLimit(2...5)
            DictationField(text: $draft.notes)
        }
    }

    private func save() {
        if isNew {
            setup.add(draft)
            onCreated?(draft)
        } else {
            setup.update(draft)
        }
        dismiss()
    }
}
