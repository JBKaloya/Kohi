import SwiftUI

/// Adding or editing one thing in the cupboard.
///
/// The form shows only the fields that apply to the kind. Typing a brand or
/// model offers the bundled catalogue; picking a row fills the rest. A custom
/// entry is still a first-class record.
struct EquipmentSheet: View {
    @Environment(SetupStore.self) private var setup
    @Environment(\.dismiss) private var dismiss

    @State private var draft: Equipment
    @State private var isNew: Bool
    @State private var appliedRef: String?
    @State private var isConfirmingDelete = false
    @State private var tapCount = 0
    @State private var showCatalog = false

    /// Editing an existing item.
    init(equipment: Equipment) {
        _draft = State(initialValue: equipment)
        _isNew = State(initialValue: false)
    }

    /// A blank item of a given kind.
    init(kind: EquipmentKind) {
        _draft = State(initialValue: Equipment(kind: kind))
        _isNew = State(initialValue: true)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(spacing: 16) {
                        TextRow(label: "Brand", text: $draft.brand, placeholder: brandPlaceholder, presence: .useful)
                        TextRow(label: "Model", text: $draft.model, placeholder: modelPlaceholder, presence: .useful)
                    }

                    if showingSuggestions { suggestionSection }
                    if isNew, draft.kind == .grinder || draft.kind == .brewer {
                        Button("Browse catalogue") { showCatalog = true }
                            .catalogueLabel()
                    }

                    switch draft.kind {
                    case .grinder: grinderSection
                    case .brewer: brewerSection
                    case .espressoMachine: espressoSection
                    case .kettle: kettleSection
                    case .scale: scaleSection
                    case .accessory: EmptyView()
                    }

                    if draft.kind == .grinder { rangesSection }

                    defaultsSection
                    notesSection

                    if !isNew { deleteRow }
                }
                .padding(.horizontal, 26)
                .padding(.top, 14)
                .padding(.bottom, 44)
                .fieldKeyboardClearance()
            }
            .scrollIndicators(.hidden)
            .background(Palette.paper.ignoresSafeArea())
            .navigationTitle(isNew ? "Add \(draft.kind.label.lowercased())" : draft.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.medium)
                        .disabled(draft.displayName == draft.kind.label)
                }
            }
        }
        .tint(Palette.ink)
        .haptic(.tap, trigger: tapCount)
        .onChange(of: query) { _, new in
            if new.isEmpty { appliedRef = nil }
        }
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
        .sheet(isPresented: $showCatalog) {
            CatalogPicker(
                title: draft.kind.label,
                entries: catalogEntries,
                selectedID: appliedRef,
                onPick: { entry in
                    if draft.kind == .grinder, let grinder = ReferenceBase.grinder(id: entry.id) {
                        apply(grinder)
                    } else if let brewer = ReferenceBase.brewer(id: entry.id) {
                        draft = Equipment(reference: brewer, preserving: draft)
                        appliedRef = brewer.id
                    }
                    showCatalog = false
                },
                onAddManually: { showCatalog = false }
            )
        }
    }

    // MARK: - Reference base

    /// Offered while typing. Once a product is applied the list hides — a
    /// custom entry is still a first-class record if you keep going.
    private var showingSuggestions: Bool {
        appliedRef == nil && !query.isEmpty && !suggestions.isEmpty
    }

    private var query: String {
        [draft.brand, draft.model]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private var suggestions: [ReferenceBase.Item] {
        ReferenceBase.equipment(kind: draft.kind, matching: query)
    }

    private var catalogEntries: [CatalogEntry] {
        if draft.kind == .grinder {
            return ReferenceBase.grinders.map { $0.catalogEntry(owned: false) }
        }
        return ReferenceBase.brewers.map { $0.catalogEntry(owned: false) }
    }

    private var suggestionSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(suggestions) { item in
                Button {
                    apply(item)
                } label: {
                    VStack(spacing: 9) {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(item.displayName)
                                .font(Typography.value)
                                .foregroundStyle(Palette.ink)
                                .lineLimit(1)
                            Spacer()
                            if let family = item.family {
                                Text(family.label)
                                    .catalogueLabel()
                            }
                        }
                        Rectangle().fill(Palette.hairline).frame(height: 1)
                    }
                    .padding(.vertical, 11)
                }
                .buttonStyle(.plain)
            }

            Text("Or keep typing — a custom entry is a first-class record.")
                .font(Typography.tag)
                .foregroundStyle(Palette.inkMuted)
                .padding(.top, 8)
        }
    }

    private func apply(_ item: ReferenceBase.Item) {
        tapCount += 1
        withAnimation(Motion.quick) {
            if draft.kind == .grinder, let grinder = ReferenceBase.grinder(id: item.id) {
                apply(grinder)
            } else if let brewer = ReferenceBase.brewer(id: item.id) {
                draft = Equipment(reference: brewer, preserving: draft)
            } else {
                draft = Equipment(reference: item, preserving: draft)
            }
        }
        appliedRef = item.id
    }

    private func apply(_ reference: ReferenceBase.Grinder) {
        tapCount += 1
        withAnimation(Motion.quick) {
            draft = Equipment(
                id: draft.id,
                kind: .grinder,
                brand: reference.brand,
                model: reference.model,
                notes: draft.notes,
                isDefaultFor: draft.isDefaultFor,
                grinderRef: reference.id,
                burrType: reference.burrType,
                burrMm: reference.burrMm,
                adjustment: reference.adjustment,
                stepsPerRotation: reference.stepsPerRotation,
                makerMicronsPerStep: reference.makerMicronsPerStep,
                // Your declared ranges outrank the base's hints, always.
                ranges: draft.ranges.isEmpty ? (reference.ranges ?? []) : draft.ranges,
                createdAt: draft.createdAt
            )
        }
    }

    // MARK: - Per-kind fields

    private var grinderSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            FormField(label: "Burrs") {
                ChipPicker(
                    items: BurrType.allCases,
                    label: \.label,
                    selection: $draft.burrType,
                    onPick: { tapCount += 1 }
                )
            }
            NumberRow("Burr size", value: $draft.burrMm, unit: "mm")
            FormField(label: "Adjustment") {
                ChipPicker(
                    items: GrindAdjustment.allCases,
                    label: \.label,
                    selection: $draft.adjustment,
                    onPick: { tapCount += 1 }
                )
            }
            NumberRow("Steps / turn", value: $draft.stepsPerRotation)
            NumberRow("Per step", value: $draft.makerMicronsPerStep, unit: "µm")

            Text("""
            Microns per step is the maker's figure for how far the burr moves — \
            not the size of the grounds. It is good for scaling within this \
            grinder, and misleading between two.
            """)
            .font(Typography.tag)
            .foregroundStyle(Palette.inkMuted)
        }
    }

    private var brewerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextRow(label: "Type", text: $draft.brewerType.orEmpty, placeholder: Placeholders.text(.brewerModel))
            Text("Accepts").catalogueLabel()
            ChipPicker(
                items: Array(FilterShape.allCases),
                label: \.label,
                selection: Binding(
                    get: { draft.acceptsFilterShapes.first },
                    set: { shape in
                        if let shape { draft.acceptsFilterShapes = [shape] }
                    }
                ),
                allowsDeselect: true,
                onPick: { tapCount += 1 }
            )
        }
    }

    private var espressoSection: some View {
        VStack(spacing: 16) {
            NumberRow("Basket", value: $draft.basketG, unit: "g", placeholder: Placeholders.text(.espressoBasket))
            NumberRow("Pressure", value: $draft.pressureBar, unit: "bar", placeholder: Placeholders.text(.espressoPressure))
        }
    }

    private var kettleSection: some View {
        VStack(spacing: 16) {
            FormField(label: "Spout") {
                Toggle("Gooseneck", isOn: $draft.isGooseneck.orFalse)
                    .labelsHidden()
            }
            FormField(label: "Temp control") {
                Toggle("Temperature control", isOn: $draft.hasTemperatureControl.orFalse)
                    .labelsHidden()
            }
        }
    }

    private var scaleSection: some View {
        VStack(spacing: 16) {
            NumberRow("Resolution", value: $draft.resolutionG, unit: "g", placeholder: Placeholders.text(.scaleResolution))
            FormField(label: "Timer") {
                Toggle("Built-in timer", isOn: $draft.hasTimer.orFalse)
                    .labelsHidden()
            }
        }
    }

    // MARK: - Ranges

    /// The settings that work for you, per method. This is the field the grind
    /// conversion actually runs on — without it, translating a reference recipe
    /// falls back to the base's indicative hints and says so.
    private var rangesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(Copy.setYourRange)
                    .catalogueLabel()
                Spacer()
                Button("Later", action: save)
                    .catalogueLabel()
                    .disabled(draft.displayName == draft.kind.label)
            }

            ForEach(BrewMethod.allCases) { method in
                rangeRow(method)
            }

            Text("Leave a method blank if you have not settled on it yet. \(Placeholders.text(.grinderRange))")
                .font(Typography.tag)
                .foregroundStyle(Palette.inkMuted)
        }
    }

    private func rangeRow(_ method: BrewMethod) -> some View {
        let range = draft.range(for: method)
        return VStack(spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(method.label)
                    .catalogueLabel()
                    .frame(width: 92, alignment: .leading)

                TextField("low", text: rangeBinding(method, isLow: true))
                    .formValue()
                    .keyboardType(.decimalPad)
                    .frame(width: 52)

                Text("–")
                    .font(Typography.value)
                    .foregroundStyle(range == nil ? Palette.hairline : Palette.inkMuted)

                TextField("high", text: rangeBinding(method, isLow: false))
                    .formValue()
                    .keyboardType(.decimalPad)
                    .frame(width: 52)

                Spacer()

                if range != nil, !unitLabel.isEmpty {
                    Text(unitLabel)
                        .font(Typography.tag)
                        .foregroundStyle(Palette.inkMuted)
                }
            }
            Rectangle().fill(Palette.hairline).frame(height: 1)
        }
    }

    private var unitLabel: String {
        switch draft.adjustment {
        case .clicks: "clicks"
        case .dial: "on the dial"
        case .stepless, .none: ""
        }
    }

    /// Writing one half of a range with the other still empty is normal while
    /// typing, so a half-filled row keeps the value and mirrors it until the
    /// second number arrives.
    private func rangeBinding(_ method: BrewMethod, isLow: Bool) -> Binding<String> {
        Binding(
            get: {
                guard let range = draft.range(for: method) else { return "" }
                return GrindRange.number(isLow ? range.low : range.high)
            },
            set: { text in
                let existing = draft.range(for: method)
                let typed = NumberText.parse(text)
                let low = isLow ? typed : existing?.low
                let high = isLow ? existing?.high : typed

                draft.ranges.removeAll { $0.method == method }
                if let low, let high {
                    draft.ranges.append(GrindRange(method: method, low: low, high: high))
                } else if let single = low ?? high {
                    draft.ranges.append(GrindRange(method: method, low: single, high: single))
                }
                draft.ranges.sort { $0.method.rawValue < $1.method.rawValue }
            }
        )
    }

    // MARK: - Defaults and notes

    private var defaultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Default for")
                .catalogueLabel()

            ChipToggles(
                items: BrewMethod.allCases,
                label: \.label,
                isOn: { draft.isDefaultFor.contains($0) },
                toggle: { method, on in
                    tapCount += 1
                    if on {
                        if !draft.isDefaultFor.contains(method) { draft.isDefaultFor.append(method) }
                    } else {
                        draft.isDefaultFor.removeAll { $0 == method }
                    }
                }
            )

            Text("Pre-fills a new brew. One item of each kind per method.")
                .font(Typography.tag)
                .foregroundStyle(Palette.inkMuted)
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Notes")
                .catalogueLabel()
            TextField(notesPlaceholder, text: $draft.notes, axis: .vertical)
                .formValue()
                .lineLimit(2...5)
            DictationField(text: $draft.notes)
            Rectangle().fill(Palette.hairline).frame(height: 1)
        }
    }

    private var deleteRow: some View {
        Button("Remove from setup") { isConfirmingDelete = true }
            .font(Typography.tag)
            .foregroundStyle(Palette.inkMuted)
            .padding(.top, 6)
    }

    private var brandPlaceholder: String {
        switch draft.kind {
        case .grinder: Placeholders.text(.grinderBrand)
        case .brewer: Placeholders.text(.brewerBrand)
        case .espressoMachine: Placeholders.text(.espressoBrand)
        case .kettle: Placeholders.text(.kettleBrand)
        case .scale: Placeholders.text(.scaleBrand)
        case .accessory: Placeholders.text(.accessoryName)
        }
    }

    private var modelPlaceholder: String {
        switch draft.kind {
        case .grinder: Placeholders.text(.grinderModel)
        case .brewer: Placeholders.text(.brewerModel)
        case .espressoMachine: Placeholders.text(.espressoModel)
        case .kettle: Placeholders.text(.kettleModel)
        case .scale: Placeholders.text(.scaleModel)
        case .accessory: ""
        }
    }

    private var notesPlaceholder: String {
        draft.kind == .accessory ? Placeholders.text(.accessoryNotes) : ""
    }

    // MARK: - Save

    private func save() {
        // The default flags are applied through the store, which clears the
        // same role from anything else of this kind.
        let methods = draft.isDefaultFor
        var stored = draft
        stored.isDefaultFor = []
        if let first = stored.filters.first, !first.isEmpty {
            stored.filterBrand = first.brand
            stored.filterShape = first.shape
        }

        if isNew {
            setup.add(stored)
        } else {
            setup.update(stored)
        }
        for method in methods {
            setup.setDefault(stored, for: method, on: true)
        }
        dismiss()
    }
}

extension Binding where Value == String? {
    /// An optional string edited as a plain one: blank means absent.
    var orEmpty: Binding<String> {
        Binding<String>(
            get: { wrappedValue ?? "" },
            set: { wrappedValue = $0.isEmpty ? nil : $0 }
        )
    }
}

extension Binding where Value == Bool? {
    /// A tri-state flag edited as a toggle. "Off" and "never said" look the
    /// same in a form, and for these fields they mean the same thing.
    var orFalse: Binding<Bool> {
        Binding<Bool>(
            get: { wrappedValue ?? false },
            set: { wrappedValue = $0 }
        )
    }
}
