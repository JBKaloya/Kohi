import SwiftUI

/// The one form in the app. Quiet rows, quick picks where a card has a small
/// vocabulary, free text everywhere else.
struct CardEditSheet: View {
    @State private var draft: CoffeeCard
    private let isNew: Bool
    private let extract: (@Sendable () async -> ParsedFields)?
    private let onSave: (CoffeeCard) -> Void
    private let onDiscard: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var isReading = false
    @State private var isSearchingPlace = false
    @State private var saveTrigger = 0

    init(
        card: CoffeeCard,
        isNew: Bool,
        extract: (@Sendable () async -> ParsedFields)? = nil,
        onSave: @escaping (CoffeeCard) -> Void,
        onDiscard: (() -> Void)? = nil
    ) {
        _draft = State(initialValue: card)
        self.isNew = isNew
        self.extract = extract
        self.onSave = onSave
        self.onDiscard = onDiscard
    }

    private static let processPicks = [
        "Washed", "Natural", "Honey", "Anaerobic", "Carbonic Maceration", "Wet Hulled",
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    if isReading { readingIndicator }

                    VStack(spacing: 16) {
                        field("Coffee", text: $draft.name)
                        field("Roaster", text: $draft.roaster)
                        placeRow
                        field("Country", text: $draft.country)
                        field("Region", text: $draft.region)
                        field("Producer", text: $draft.producer)
                        field("Altitude", text: $draft.altitude)
                        field("Variety", text: $draft.variety)
                        field("Process", text: $draft.process)
                    }

                    group("Common processes") {
                        FlowLayout {
                            ForEach(Self.processPicks, id: \.self) { pick in
                                TagChip(text: pick, isSelected: draft.process == pick) {
                                    draft.process = draft.process == pick ? "" : pick
                                }
                            }
                        }
                    }

                    group("Tasting notes") {
                        TagField(tags: $draft.tastingNotes)
                    }

                    group("Brew method") {
                        FlowLayout {
                            ForEach(BrewMethod.allCases) { method in
                                TagChip(text: method.label, isSelected: draft.brewMethod == method) {
                                    draft.brewMethod = draft.brewMethod == method ? nil : method
                                }
                            }
                        }
                    }

                    group("Note to self") {
                        TextField("", text: $draft.personalNotes, axis: .vertical)
                            .font(Typography.body)
                            .lineLimit(3...8)
                    }

                    group("Date") {
                        DatePicker("", selection: $draft.date, displayedComponents: .date)
                            .labelsHidden()
                    }

                    if let onDiscard {
                        Button {
                            onDiscard()
                            dismiss()
                        } label: {
                            Text(isNew ? "Discard this scan" : "Remove from archive")
                                .catalogueLabel()
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 26)
                .padding(.top, 14)
                .padding(.bottom, 60)
            }
            .scrollIndicators(.hidden)
            .background(Palette.paper.ignoresSafeArea())
            .navigationTitle(isNew ? "New card" : "Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        // A new card confirms itself by landing in the grid a
                        // moment later; a second haptic here steps on it.
                        if !isNew { saveTrigger += 1 }
                        onSave(draft)
                        dismiss()
                    }
                    .fontWeight(.medium)
                }
            }
            .sheet(isPresented: $isSearchingPlace) {
                PlaceSearchView(place: $draft.place)
            }
        }
        .tint(Palette.ink)
        .haptic(.saved, trigger: saveTrigger)
        .task { await prefill() }
    }

    // MARK: - Pieces

    private func group(
        _ title: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).catalogueLabel()
            content()
        }
    }

    /// Label always visible beside the value, matching the detail view's
    /// catalogue block. A placeholder that vanishes once the field is filled
    /// leaves you guessing what "Gedeb, Gedeo" was supposed to be.
    private func field(_ label: String, text: Binding<String>) -> some View {
        row(label) {
            TextField("", text: text)
                .font(Typography.value)
                .foregroundStyle(Palette.ink)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
        }
    }

    private func row(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(label)
                    .catalogueLabel()
                    .frame(width: 74, alignment: .leading)
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Rectangle().fill(Palette.hairline).frame(height: 1)
        }
    }

    private var placeRow: some View {
        Button {
            isSearchingPlace = true
        } label: {
            row("Place") {
                Text(draft.place?.summary ?? "Search")
                    .font(Typography.value)
                    .foregroundStyle(draft.place == nil ? Palette.inkMuted : Palette.ink)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    private var readingIndicator: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.mini)
            Text("Reading the card")
                .catalogueLabel()
        }
        .transition(.opacity)
    }

    // MARK: - OCR

    /// Fills empty fields from the scan. Anything already typed wins, so a slow
    /// read never overwrites what you are in the middle of writing.
    private func prefill() async {
        guard let extract else { return }
        withAnimation(Motion.snappy) { isReading = true }
        let parsed = await extract()
        withAnimation(Motion.snappy) {
            isReading = false
            merge(parsed)
        }
    }

    private func merge(_ parsed: ParsedFields) {
        func fill(_ keyPath: WritableKeyPath<CoffeeCard, String>, _ value: String?) {
            guard let value, draft[keyPath: keyPath].isEmpty else { return }
            draft[keyPath: keyPath] = value
        }
        fill(\.name, parsed.name)
        fill(\.roaster, parsed.roaster)
        fill(\.country, parsed.country)
        fill(\.region, parsed.region)
        fill(\.producer, parsed.producer)
        fill(\.altitude, parsed.altitude)
        fill(\.variety, parsed.variety)
        fill(\.process, parsed.process)
        if draft.tastingNotes.isEmpty { draft.tastingNotes = parsed.tastingNotes }
    }
}
