import SwiftUI

/// Create or edit a recipe in Mine.
///
/// Opened with `recipe: nil` (default) it starts blank and calls `recipes.add`.
/// Opened with an existing recipe it pre-fills every field and calls
/// `recipes.update` on Save, so renaming or tweaking parameters never
/// creates a duplicate.
struct RecipeEditSheet: View {
    @Environment(RecipeStore.self) private var recipes
    @Environment(\.dismiss) private var dismiss

    private let existing: Recipe?
    @State private var draft: Recipe
    @State private var tapCount = 0
    @State private var showSteps = false
    @State private var nameError: String?
    @State private var rejectTrigger = 0

    init(recipe: Recipe? = nil) {
        existing = recipe
        _draft = State(initialValue: recipe ?? Recipe())
    }

    private var isEditing: Bool { existing != nil }
    private var title: String { isEditing ? "Edit recipe" : Copy.newRecipe }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    FieldGroup(title: isEditing ? "Recipe" : Copy.newRecipe) {
                        TextRow(
                            label: "Name",
                            text: $draft.name,
                            placeholder: "Name this recipe",
                            presence: .useful,
                            error: nameError
                        )
                        DictationField(text: $draft.name)
                        RollingPicker(
                            label: "Method",
                            options: BrewMethod.allCases.map {
                                RollOption(id: $0, name: $0.label)
                            },
                            selection: Binding(
                                get: { draft.method ?? .v60 },
                                set: {
                                    draft.method = $0
                                    tapCount += 1
                                }
                            )
                        )
                    }

                    FieldGroup(title: "Parameters") {
                        RollingCounter("Dose", value: $draft.dose, range: .dose, unit: "g", labelWidth: 74)
                        if draft.method == .espresso {
                            RollingCounter("Out", value: $draft.beverage, range: .beverage, unit: "g", labelWidth: 74)
                        } else {
                            RollingCounter("Water", value: $draft.water, range: .water, unit: "g", labelWidth: 74)
                        }
                        RollingCounter("Temp", value: $draft.temperature, range: .temperature, unit: "°C", labelWidth: 74)
                        RollingCounter("Time", value: secondsBinding, range: .brewTime, unit: "s", labelWidth: 74)
                        TextRow(label: "Grind", text: $draft.grindLabel, placeholder: "medium-fine",
                                capitalization: .never)
                    }

                    FieldGroup(title: "Steps") {
                        Button("Edit steps") { showSteps = true }
                            .catalogueLabel()
                        if !draft.steps.isEmpty {
                            ForEach(draft.steps) { step in
                                Text(step.instruction)
                                    .font(Typography.tag)
                                    .foregroundStyle(Palette.inkMuted)
                            }
                        }
                    }
                }
                .padding(.horizontal, 26)
                .padding(.top, 16)
                .padding(.bottom, 44)
                .fieldKeyboardClearance()
            }
            .scrollIndicators(.hidden)
            .background(Palette.paper.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.medium)
                }
            }
            .onChange(of: draft.name) { _, _ in
                if !trimmedName.isEmpty { nameError = nil }
            }
        }
        .tint(Palette.ink)
        .haptic(.tap, trigger: tapCount)
        .haptic(.deleted, trigger: rejectTrigger)
        .sheet(isPresented: $showSteps) {
            StepBuilderSheet(draft: draft) { recipe in
                draft.steps = recipe.steps
                draft.name = recipe.name
                draft.dose = recipe.dose
                draft.water = recipe.water
                draft.beverage = recipe.beverage
            }
        }
    }

    private var secondsBinding: Binding<Double?> {
        Binding(
            get: { draft.seconds.map(Double.init) },
            set: { draft.seconds = $0.map { Int($0.rounded()) } }
        )
    }

    private var trimmedName: String {
        draft.name.trimmingCharacters(in: .whitespaces)
    }

    private func save() {
        guard !trimmedName.isEmpty else {
            nameError = FieldCopy.recipeNameMissing
            rejectTrigger += 1
            return
        }
        draft.source = .mine
        draft.autoAdvance = false
        if isEditing {
            recipes.update(draft)
        } else {
            recipes.add(draft)
        }
        dismiss()
    }
}
