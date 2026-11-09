import SwiftUI

/// One coffee had in a coffee shop: the coffee, the visit, how it was.
///
/// Reads the store by id so an edit shows at once, and so a tasting deleted
/// on another phone simply closes.
struct TastingDetailView: View {
    let tastingID: UUID
    /// False when pushed from the card it links, so the card is not stacked
    /// on top of itself.
    var opensCard = true
    /// False when pushed from its place.
    var opensPlace = true

    @Environment(TastingStore.self) private var tastings
    @Environment(CardStore.self) private var store
    @Environment(\.appEnvironment) private var appEnvironment
    @Environment(\.dismiss) private var dismiss

    @State private var editing = false
    @State private var confirmsDelete = false
    @State private var openedCard: CoffeeCard?
    @State private var openedPlace: PlaceGroup?
    @State private var deleteTrigger = 0

    private var tasting: Tasting? { tastings.tasting(id: tastingID) }

    private var card: CoffeeCard? {
        tasting?.cardID.flatMap { store.card(id: $0) }
    }

    var body: some View {
        Group {
            if let tasting {
                content(tasting)
            } else {
                Color.clear.onAppear { dismiss() }
            }
        }
        .background(Palette.paper.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Edit") { editing = true }
                    Button("Delete", role: .destructive) { confirmsDelete = true }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("More")
            }
        }
        .tint(Palette.ink)
        .haptic(.deleted, trigger: deleteTrigger)
        .sheet(isPresented: $editing) {
            if let tasting {
                TastingComposeSheet(editing: tasting)
                    .appEnvironment(appEnvironment)
            }
        }
        .confirmationDialog("Delete this tasting?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                guard let tasting else { return }
                deleteTrigger += 1
                tastings.delete(tasting)
                dismiss()
            }
        }
        .navigationDestination(item: $openedCard) { card in
            CardDetailView(card: card)
                .appEnvironment(appEnvironment)
        }
        .navigationDestination(item: $openedPlace) { group in
            PlaceTastingsView(place: group.place, placeID: group.placeID)
                .appEnvironment(appEnvironment)
        }
    }

    private func content(_ tasting: Tasting) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                coffee(tasting)
                experience(tasting)
                evaluation(tasting)
            }
            .padding(.horizontal, 28)
            .padding(.top, 12)
            .padding(.bottom, 60)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Coffee

    private func coffee(_ tasting: Tasting) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tasting.coffeeName(fallback: card.map { store.title(for: $0) } ?? ""))
                .font(Typography.title)
                .foregroundStyle(Palette.ink)
            let roaster = tasting.coffee.roaster.trimmingCharacters(in: .whitespaces)
            if !roaster.isEmpty {
                Text(roaster)
                    .font(Typography.subtitle)
                    .foregroundStyle(Palette.inkMuted)
            }
            let origin = [tasting.coffee.originLine, tasting.coffee.process]
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                .joined(separator: " · ")
            if !origin.isEmpty {
                Text(origin)
                    .font(Typography.tag)
                    .foregroundStyle(Palette.inkMuted)
            }
            if !tasting.coffee.tastingNotes.isEmpty {
                Text(tasting.coffee.tastingNotes.joined(separator: ", "))
                    .font(Typography.tag)
                    .foregroundStyle(Palette.inkMuted)
            }
            if opensCard, let card {
                Button { openedCard = card } label: {
                    Text(Copy.openInCoffeeCollection).catalogueLabel()
                }
                .buttonStyle(.plain)
                .touchTarget()
            }
        }
    }

    // MARK: - Experience

    private func experience(_ tasting: Tasting) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Copy.yourVisit).catalogueLabel()
            if let place = tasting.place {
                Button {
                    guard opensPlace else { return }
                    openedPlace = PlaceKey.group(tastings.tastings).first {
                        PlaceKey.same($0.place, $0.placeID, place, tasting.placeID)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(place.name)
                            .font(Typography.value)
                            .foregroundStyle(Palette.ink)
                        if opensPlace {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Palette.inkMuted)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(!opensPlace)
            }
            Text(experienceLine(tasting))
                .font(Typography.tag)
                .foregroundStyle(Palette.inkMuted)
            if !tasting.photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(tasting.photos, id: \.self) { name in
                            TastingPhotoThumb(tastingID: tasting.id, name: name, size: 120)
                        }
                    }
                }
            }
        }
    }

    private func experienceLine(_ tasting: Tasting) -> String {
        var parts = [CatalogueDate.happened(tasting.date)]
        if let method = tasting.methodLine { parts.append(method) }
        if let price = tasting.price { parts.append(price.formatted) }
        return parts.joined(separator: " · ")
    }

    // MARK: - Evaluation

    @ViewBuilder
    private func evaluation(_ tasting: Tasting) -> some View {
        let scored = tasting.ratingHalves != nil || !tasting.taste.isEmpty || !tasting.flavors.isEmpty
        let note = tasting.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if scored || !note.isEmpty {
            VStack(alignment: .leading, spacing: 18) {
                Text(Copy.yourTasting).catalogueLabel()
                if let halves = tasting.ratingHalves {
                    HStack(spacing: 8) {
                        RatingDots(halves: halves)
                        Text(HalfRating.text(halves))
                            .font(Typography.tag)
                            .monospacedDigit()
                            .foregroundStyle(Palette.inkMuted)
                            .accessibilityHidden(true)
                    }
                }
                if !tasting.taste.isEmpty {
                    TasteRadar(taste: tasting.taste)
                        .frame(maxWidth: .infinity)
                }
                if !tasting.flavors.isEmpty {
                    FlowLayout {
                        ForEach(tasting.flavors, id: \.id) { flavor in
                            TagChip(
                                text: flavor.intensity.map { "\(flavor.displayName) · \(FlavorTag.intensityLabel($0).lowercased())" }
                                    ?? flavor.displayName,
                                isSelected: true
                            ) {}
                                .allowsHitTesting(false)
                        }
                    }
                }
                if !note.isEmpty {
                    Text(note)
                        .font(Typography.body)
                        .foregroundStyle(Palette.ink)
                }
            }
        }
    }
}
