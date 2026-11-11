import SwiftUI

/// The coffee of a brew logged without one: what you remember of it, then
/// the card it belongs to, or a new card made from what you wrote.
struct LinkCoffeeSheet: View {
    @Binding var coffee: TastedCoffee
    let onLink: (CoffeeCard) -> Void

    @Environment(CardStore.self) private var store
    @Environment(\.appEnvironment) private var appEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var newCard: CoffeeCard?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    FieldGroup(title: Copy.coffee) {
                        TextRow(label: "Name", text: $coffee.name)
                        TextRow(label: "Roaster", text: $coffee.roaster)
                    }
                    Button(Copy.newCardFromThis) {
                        newCard = CoffeeCard(told: coffee)
                    }
                    .catalogueLabel()
                    .touchTarget()
                    .disabled(coffee.trimmedName.isEmpty)
                    if !store.cards.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(Copy.linkToACoffee).catalogueLabel()
                                .padding(.bottom, 6)
                            ForEach(candidates) { card in
                                Button {
                                    onLink(card)
                                    dismiss()
                                } label: {
                                    HStack {
                                        Text(store.title(for: card))
                                            .font(Typography.value)
                                            .foregroundStyle(Palette.ink)
                                        Spacer()
                                    }
                                    .padding(.vertical, 14)
                                    .frame(minHeight: 44)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                Rectangle().fill(Palette.hairline).frame(height: 1)
                            }
                        }
                    }
                }
                .padding(.horizontal, 26)
                .padding(.top, 16)
                .padding(.bottom, 44)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(Palette.paper.ignoresSafeArea())
            .navigationTitle(Copy.addTheCoffee)
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneButton()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.medium)
                }
            }
        }
        .tint(Palette.ink)
        .sheet(item: $newCard) { draft in
            CardEditSheet(card: draft, isNew: true) { saved in
                store.add(saved)
                onLink(store.card(id: saved.id) ?? saved)
                dismiss()
            }
            .appEnvironment(appEnvironment)
        }
    }

    /// The cards that read like what was written come first.
    private var candidates: [CoffeeCard] {
        let name = coffee.trimmedName.lowercased()
        let roaster = coffee.roaster.trimmingCharacters(in: .whitespaces).lowercased()
        func score(_ card: CoffeeCard) -> Int {
            var points = 0
            if !name.isEmpty, card.displayName.lowercased().contains(name) { points += 2 }
            if !roaster.isEmpty, card.roaster.lowercased().contains(roaster) { points += 1 }
            return points
        }
        return store.cards.sorted { lhs, rhs in
            let l = score(lhs), r = score(rhs)
            if l != r { return l > r }
            return lhs.createdAt > rhs.createdAt
        }
    }
}

extension CoffeeCard {
    /// A new card holding what was told about a coffee, before any scan.
    init(told: TastedCoffee) {
        self.init(name: told.trimmedName, roaster: told.roaster, roasterId: told.roasterId)
        country = told.country
        region = told.region
        farm = told.farm.isEmpty ? nil : told.farm
        variety = told.variety
        process = told.process
        tastingNotes = told.tastingNotes
    }
}
