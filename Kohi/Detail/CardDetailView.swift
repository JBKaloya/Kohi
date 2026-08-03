import SwiftUI

/// The card as an archival object: cut out, centred on paper, lit by a soft
/// shadow, with its catalogue entry set underneath.
struct CardDetailView: View {
    let card: CoffeeCard

    @Environment(CardStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var deleteTrigger = 0
    @State private var isEditing = false

    /// Reads through the store so edits made elsewhere show up here.
    private var live: CoffeeCard { store.card(id: card.id) ?? card }

    var body: some View {
        GeometryReader { proxy in
            let objectWidth = proxy.size.width * Motion.Object.widthFraction

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    tombstone
                        .padding(.horizontal, 28)
                        .padding(.top, 18)

                    CardObject(card: live, width: objectWidth)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 52)

                    VStack(alignment: .leading, spacing: 30) {
                        Text(live.displayName)
                            .font(Typography.title)
                            .foregroundStyle(Palette.ink)

                        if !live.tastingNotes.isEmpty {
                            notes
                        }

                        CaptionBlock(card: live)

                        if !live.personalNotes.trimmingCharacters(in: .whitespaces).isEmpty {
                            personal
                        }

                        actions
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 72)
                }
            }
            .scrollIndicators(.hidden)
        }
        .background(Palette.paper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .haptic(.deleted, trigger: deleteTrigger)
        .sheet(isPresented: $isEditing) {
            CardEditSheet(card: live, isNew: false) { store.update($0) }
        }
    }

    /// The small line the book pages put above the plate.
    private var tombstone: some View {
        Text(
            [live.displayName, live.originLine, live.altitude]
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
        )
        .catalogueLabel()
        .textCase(nil)
        .lineLimit(2)
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Notes")
                .catalogueLabel()
            HStack(spacing: 7) {
                ForEach(live.tastingNotes, id: \.self) { note in
                    Text(note)
                        .font(Typography.tag)
                        .foregroundStyle(Palette.ink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .overlay(
                            Capsule().stroke(Palette.hairline, lineWidth: 1)
                        )
                }
            }
        }
    }

    private var personal: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Note to self")
                .catalogueLabel()
            Text(live.personalNotes)
                .font(Typography.body)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actions: some View {
        HStack(spacing: 22) {
            Button { isEditing = true } label: {
                Text("Edit")
                    .catalogueLabel()
                    .foregroundStyle(Palette.ink)
            }
            Button {
                deleteTrigger += 1
                dismiss()
                store.delete(live)
            } label: {
                Text("Remove from archive")
                    .catalogueLabel()
            }
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
    }
}
