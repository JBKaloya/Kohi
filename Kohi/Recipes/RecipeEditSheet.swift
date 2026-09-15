import SwiftUI

/// A blank recipe, named and saved into Mine.
struct RecipeEditSheet: View {
    @Environment(RecipeStore.self) private var recipes
    @Environment(\.dismiss) private var dismiss

    @State private var draft = Recipe()
    @State private var tapCount = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    FieldGroup(title: Copy.newRecipe) {
                        TextRow(
                            label: "Name",
                            text: $draft.name,
                            placeholder: Placeholders.text(.recipeName),
                            presence: .useful
                        )
                        DictationField(text: $draft.name)
                        FormField(label: "Method") {
                            ChipPicker(
                                items: BrewMethod.allCases,
                                label: \.label,
                                selection: methodBinding,
                                allowsDeselect: false,
                                onPick: { tapCount += 1 }
                            )
                        }
                    }

                    FieldGroup(title: "Parameters") {
                        NumberRow("Dose", value: $draft.dose, unit: "g", labelWidth: 74)
                        NumberRow("Water", value: $draft.water, unit: "g", labelWidth: 74)
                        NumberRow("Temp", value: $draft.temperature, unit: "°C", labelWidth: 74)
                        NumberRow("Time", value: secondsBinding, unit: "s", labelWidth: 74)
                        TextRow(label: "Grind", text: $draft.grindLabel, placeholder: "medium-fine")
                    }

                    FieldGroup(title: "Steps") {
                        Text("Add pours after saving, or brew once and Save as recipe.")
                            .font(Typography.tag)
                            .foregroundStyle(Palette.inkMuted)
                    }
                }
                .padding(.horizontal, 26)
                .padding(.top, 16)
                .padding(.bottom, 44)
                .fieldKeyboardClearance()
            }
            .scrollIndicators(.hidden)
            .background(Palette.paper.ignoresSafeArea())
            .navigationTitle(Copy.newRecipe)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        draft.source = .mine
                        draft.autoAdvance = false
                        recipes.add(draft)
                        dismiss()
                    }
                    .fontWeight(.medium)
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .tint(Palette.ink)
        .haptic(.tap, trigger: tapCount)
    }

    private var methodBinding: Binding<BrewMethod?> {
        Binding(
            get: { draft.method },
            set: { if let value = $0 { draft.method = value } }
        )
    }

    private var secondsBinding: Binding<Double?> {
        Binding(
            get: { draft.seconds.map(Double.init) },
            set: { draft.seconds = $0.map { Int($0.rounded()) } }
        )
    }
}
