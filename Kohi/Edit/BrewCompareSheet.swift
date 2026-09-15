import SwiftUI

struct BrewCompareSheet: View {
    let card: CoffeeCard
    let reference: Brew
    var others: [CoffeeCard]
    var waters: [WaterProfile]
    var equipment: [Equipment]
    var onAgain: (Brew) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var other: Brew?
    @State private var anyCoffee = false

    init(
        card: CoffeeCard,
        reference: Brew,
        others: [CoffeeCard] = [],
        waters: [WaterProfile] = [],
        equipment: [Equipment] = [],
        onAgain: @escaping (Brew) -> Void = { _ in }
    ) {
        self.card = card
        self.reference = reference
        self.others = others
        self.waters = waters
        self.equipment = equipment
        self.onAgain = onAgain
        let previous = card.brews.first { $0.id != reference.id && $0.isComparable }
        _other = State(initialValue: previous)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    picker
                    if let other {
                        comparison(of: other)
                    }
                }
                .padding(.horizontal, 26)
                .padding(.top, 14)
                .padding(.bottom, 60)
            }
            .scrollIndicators(.hidden)
            .background(Palette.paper.ignoresSafeArea())
            .navigationTitle("Compare")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.medium)
                }
            }
        }
        .tint(Palette.ink)
    }

    private var eligible: [Brew] {
        let pool = anyCoffee
            ? others.flatMap(\.brews).filter { $0.method == reference.method }
            : card.brews
        return pool
            .filter { $0.id != reference.id && $0.isComparable }
            .sorted { $0.date > $1.date }
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                chip("Previous", selected: other?.id == eligible.first?.id) {
                    other = eligible.first
                }
                if let best = eligible.max(by: { ($0.rating ?? 0) < ($1.rating ?? 0) }) {
                    chip("Best", selected: other?.id == best.id) {
                        other = best
                    }
                }
                chip("Any coffee", selected: anyCoffee) {
                    anyCoffee.toggle()
                }
            }
            ForEach(eligible.prefix(8)) { brew in
                Button { other = brew } label: {
                    HStack {
                        Text(brew.date.formatted(.dateTime.day().month(.abbreviated)))
                            .font(Typography.tag)
                            .foregroundStyle(Palette.inkMuted)
                        Text(brew.method?.label ?? "")
                            .font(Typography.tag)
                        if let ratio = brew.ratio {
                            Text(ratio).font(Typography.tag)
                        }
                        Spacer()
                        if other?.id == brew.id {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Palette.ink)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func comparison(of other: Brew) -> some View {
        let compared = BrewComparison.of(reference, against: other, waters: waters, equipment: equipment)
        return VStack(alignment: .leading, spacing: 18) {
            HStack {
                Spacer()
                TasteRadar(taste: reference.taste, previous: other.taste)
                Spacer()
            }

            VStack(spacing: 0) {
                ForEach(compared.parameterDeltas) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(row.label)
                            .catalogueLabel()
                            .frame(width: 74, alignment: .leading)
                        Text(row.a).font(Typography.tag).frame(maxWidth: .infinity, alignment: .leading)
                        Text(row.b).font(Typography.tag).frame(maxWidth: .infinity, alignment: .leading)
                        Text(row.delta)
                            .font(Typography.tag)
                            .foregroundStyle(row.changed ? Palette.ink : Palette.inkMuted)
                    }
                    .padding(.vertical, 8)
                    Rectangle().fill(Palette.hairline).frame(height: 1)
                }
            }

            flavorLine("Both", compared.common)
            flavorLine("Only this", compared.onlyA)
            flavorLine("Only that", compared.onlyB)

            if let sentence = compared.sentence {
                Text(sentence)
                    .font(Typography.body)
                    .foregroundStyle(Palette.ink)
            }

            HStack(spacing: 18) {
                Button("Brew again from A") { onAgain(reference); dismiss() }
                Button("Brew again from B") { onAgain(other); dismiss() }
            }
            .font(Typography.label)
            .tracking(Typography.labelTracking)
            .textCase(.uppercase)
            .foregroundStyle(Palette.inkMuted)
        }
    }

    private func flavorLine(_ title: String, _ tags: [FlavorTag]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).catalogueLabel()
            if tags.isEmpty {
                Text("—").font(Typography.tag).foregroundStyle(Palette.inkMuted)
            } else {
                FlowLayout {
                    ForEach(tags) { tag in
                        TagChip(text: tag.displayName, isSelected: false) {}
                    }
                }
            }
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        TagChip(text: title, isSelected: selected, action: action)
    }
}
