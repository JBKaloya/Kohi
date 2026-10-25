import SwiftUI

/// Search the seed, or declare a custom paper. Pre-filtered by the shapes
/// of owned brewers when any exist.
struct FilterSheet: View {
    @Environment(SetupStore.self) private var setup
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appEnvironment) private var appEnvironment

    var stock: FilterStock?
    var defaultFor: UUID?
    var onCreated: ((FilterStock) -> Void)?

    @State private var draft: FilterStock
    @State private var isNew: Bool
    @State private var query = ""
    @State private var isCustom = false
    @State private var isConfirmingDelete = false
    @State private var tapCount = 0
    @State private var didSave = false
    @State private var persistOnDismiss = true

    init(
        stock: FilterStock? = nil,
        defaultFor: UUID? = nil,
        onCreated: ((FilterStock) -> Void)? = nil
    ) {
        self.stock = stock
        self.defaultFor = defaultFor
        self.onCreated = onCreated
        _draft = State(initialValue: stock ?? FilterStock())
        _isNew = State(initialValue: stock == nil)
        _isCustom = State(initialValue: stock?.modelId == nil && stock != nil)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    if isNew {
                        TextRow(label: "Search", text: $query, placeholder: "Cafec, Hario, Sibarist…")
                        if !isCustom { seedList }
                        if filterMatch.unmatched {
                            Text(Copy.noPaperMatched)
                                .font(Typography.tag)
                                .foregroundStyle(Palette.inkMuted)
                        }
                        Button {
                            isCustom.toggle()
                            tapCount += 1
                        } label: {
                            Text("Custom")
                                .catalogueLabel()
                        }
                        .buttonStyle(.plain)
                    }

                    if isCustom || !isNew || draft.modelId != nil {
                        FieldGroup(title: "Paper") {
                            TextRow(
                                label: "Name",
                                text: customNameBinding,
                                placeholder: "Cafec Abaca+",
                                presence: .useful
                            )
                            FormField(label: "Shape") {
                                ChipPicker(
                                    items: Array(FilterShape.allCases),
                                    label: \.label,
                                    selection: $draft.shape,
                                    allowsDeselect: false,
                                    onPick: { tapCount += 1 }
                                )
                            }
                            TextRow(label: "Size", text: $draft.size, placeholder: "02")
                            TextRow(label: "Origin", text: originBinding, placeholder: "Japan, tabbed")
                        }
                    }

                    if let model = draft.model {
                        Text(model.notes)
                            .font(Typography.tag)
                            .foregroundStyle(Palette.inkMuted)
                    }

                    if let calibration {
                        InsightBlock(
                            title: "On your setup",
                            bodyText: calibration.sentence,
                            provenance: "Derived from your brews"
                        )
                    }

                    if !isNew {
                        Button("Remove this filter") { isConfirmingDelete = true }
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
            .navigationTitle(isNew ? "Add a filter" : draft.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        persistOnDismiss = false
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.medium)
                        .disabled(!canSave)
                }
            }
        }
        .tint(Palette.ink)
        .haptic(.tap, trigger: tapCount)
        .onDisappear {
            guard persistOnDismiss, !didSave, canSave else { return }
            persist()
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
    }

    private var seedList: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(filteredSeed) { model in
                Button {
                    tapCount += 1
                    draft.modelId = model.id
                    draft.customName = nil
                    draft.shape = model.shape
                    if draft.size.isEmpty { draft.size = model.sizes.first ?? "" }
                    isCustom = false
                } label: {
                    VStack(spacing: 9) {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(model.shortName)
                                .font(Typography.value)
                                .foregroundStyle(Palette.ink)
                                .lineLimit(1)
                            Spacer()
                            if draft.modelId == model.id {
                                CatalogueMark(text: "On", isSelected: true)
                            } else if let flow = model.flowClass, model.showsFlowClass {
                                Text(flow.tag)
                                    .catalogueLabel()
                            }
                        }
                        Text(model.model)
                            .font(Typography.tag)
                            .foregroundStyle(Palette.inkMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Rectangle().fill(Palette.hairline).frame(height: 1)
                    }
                    .padding(.vertical, 11)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var filteredSeed: [FilterModel] {
        filterMatch.items.filter { model in
            let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
            guard !needle.isEmpty else { return true }
            return model.displayName.lowercased().contains(needle)
                || model.model.lowercased().contains(needle)
                || model.id.contains(needle)
        }
    }

    private var filterMatch: (items: [FilterModel], unmatched: Bool) {
        FilterModel.filters(matching: setup.equipment(.brewer).first)
    }

    private var canSave: Bool {
        if draft.modelId != nil { return true }
        let name = (draft.customName ?? "").trimmingCharacters(in: .whitespaces)
        return !name.isEmpty && draft.shape != nil
    }

    private var customNameBinding: Binding<String> {
        Binding(
            get: { draft.customName ?? draft.model?.shortName ?? "" },
            set: { draft.customName = $0 }
        )
    }

    private var originBinding: Binding<String> {
        Binding(
            get: { draft.origin ?? "" },
            set: { draft.origin = $0.isEmpty ? nil : $0 }
        )
    }

    private var calibration: FilterCalibration.Result? {
        guard !isNew else { return nil }
        let brews = appEnvironment?.store.cards.flatMap(\.brews) ?? []
        return FilterCalibration.of(brews, stock: setup.filterStock, focusing: draft.id)
    }

    private func save() {
        didSave = true
        persist()
        dismiss()
    }

    private func persist() {
        if isNew {
            setup.add(draft, defaultFor: defaultFor)
            onCreated?(setup.filterStock(id: draft.id) ?? draft)
        } else {
            setup.update(draft)
        }
    }
}