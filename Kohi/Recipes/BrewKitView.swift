import SwiftUI

/// Method family, dripper, grinder, filter — the kit, from the catalogue.
struct BrewKitView: View {
    @Bindable var session: BrewSession
    var onBack: () -> Void
    var onClose: () -> Void
    var onNext: () -> Void

    @Environment(SetupStore.self) private var setup
    @Environment(\.appEnvironment) private var appEnvironment

    @State private var tapCount = 0
    @State private var picking: Picking?
    @State private var addingKind: EquipmentKind?
    @State private var addingFilter = false

    private enum Picking: String, Identifiable {
        case dripper, grinder, filter
        var id: String { rawValue }
    }

    /// Always the cupboard the brew actually names. A free State could sit
    /// on Espresso while the dripper was still a V60.
    private var family: BrewerFamily {
        session.tab(in: setup)
    }

    var body: some View {
        StepFlow(
            step: session.progressIndex,
            total: session.progressTotal,
            question: Copy.withWhat,
            onBack: onBack,
            onClose: onClose,
            nextTitle: "Next",
            nextEnabled: true,
            onNext: onNext
        ) {
            VStack(alignment: .leading, spacing: 28) {
                if let applied = session.lastApplication {
                    AppliedFromLastBlock(
                        change: applied.change,
                        onKeep: { session.keepLastApplication() },
                        onUndo: { session.undoLastApplication() }
                    )
                }
                TabRail(
                    tabs: BrewKit.journeyTabs,
                    selection: Binding(
                        get: { family },
                        set: { applyFamily($0) }
                    ),
                    underline: .active,
                    title: \.label
                )

                kitRow(
                    title: family.kitTitle,
                    value: activeBrewer?.displayName,
                    empty: family == .espresso ? "Add a machine" : "Add a dripper"
                ) { picking = .dripper }

                kitRow(
                    title: "Grinder",
                    value: selectedGrinder?.displayName,
                    empty: "Add a grinder"
                ) { picking = .grinder }

                filterRow
                if !setup.accessories.isEmpty {
                    accessoriesRow
                }
            }
            .padding(.bottom, 24)
        }
        .haptic(.tap, trigger: tapCount)
        .sheet(item: $picking) { target in
            picker(for: target)
        }
        .sheet(item: $addingKind) { kind in
            EquipmentSheet(kind: kind)
                .appEnvironment(appEnvironment)
        }
        .sheet(isPresented: $addingFilter) {
            FilterSheet(defaultFor: activeBrewer?.id) { created in
                session.brew.filterStockId = created.id
                session.brew.captureSource = .typed
            }
            .appEnvironment(appEnvironment)
        }
    }

    // MARK: - Accessories

    private var accessoriesRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Accessories").catalogueLabel()
            ChipRail {
                ForEach(setup.accessories) { item in
                    let selected = session.brew.equipmentIDs.contains(item.id)
                    TagChip(text: item.displayName, isSelected: selected) {
                        tapCount += 1
                        if selected {
                            session.brew.equipmentIDs.removeAll { $0 == item.id }
                        } else {
                            session.brew.equipmentIDs.append(item.id)
                            session.brew.captureSource = .typed
                        }
                    }
                }
            }
        }
    }

    private var filterRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            kitRow(
                title: "Filter",
                value: selectedFilter?.displayName,
                empty: filterEmptyReason
            ) { picking = .filter }
            if let reason = filterReason {
                Text(reason)
                    .font(Typography.tag)
                    .foregroundStyle(Palette.inkMuted)
            }
        }
    }

    private var filterEmptyReason: String {
        if let brewer = activeBrewer, !brewer.takesPaper {
            return "No paper for a \(brewer.displayName)"
        }
        return Copy.addThePaperYouUse
    }

    private var filterReason: String? {
        if selectedFilter != nil { return nil }
        if let brewer = activeBrewer, !brewer.takesPaper {
            return "No paper for a \(brewer.displayName)"
        }
        return nil
    }

    private func kitRow(title: String, value: String?, empty: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title).catalogueLabel()
                    .frame(width: 74, alignment: .leading)
                Text(value?.isEmpty == false ? value! : empty)
                    .font(Typography.value)
                    .foregroundStyle(value == nil ? Palette.inkMuted : Palette.ink)
                    .lineLimit(1)
                Spacer()
                Text(Copy.change).catalogueLabel()
            }
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func picker(for target: Picking) -> some View {
        switch target {
        case .dripper:
            CatalogPicker(
                title: family.kitTitle,
                entries: dripperEntries,
                selectedID: activeBrewer.map { CatalogID.kit($0.id) },
                onPick: pickDripper,
                onAddManually: {
                    picking = nil
                    addingKind = family == .espresso ? .espressoMachine : .brewer
                }
            )
        case .grinder:
            CatalogPicker(
                title: "Grinder",
                entries: grinderEntries,
                selectedID: selectedGrinder.map { CatalogID.kit($0.id) },
                onPick: pickGrinder,
                onAddManually: {
                    picking = nil
                    addingKind = .grinder
                }
            )
        case .filter:
            CatalogPicker(
                title: "Filter",
                entries: filterEntries.items,
                selectedID: selectedFilter.map { CatalogID.kit($0.id) },
                unmatchedNote: filterEntries.unmatched ? Copy.noPaperMatched : filterReason,
                confirmation: Copy.addedToYourPapers,
                onPick: pickFilter,
                onAddManually: {
                    picking = nil
                    addingFilter = true
                }
            )
        }
    }

    private var dripperEntries: [CatalogEntry] {
        let owned = setup.equipment.filter {
            BrewKit.isCupboard($0.kind) && BrewKit.matches(family, $0)
        }
        var entries = owned.map { item in
            CatalogEntry(
                id: CatalogID.kit(item.id),
                title: item.displayName,
                subtitle: item.brewerKind?.label
                    ?? BrewerType.parse(item.model)?.label
                    ?? BrewerType.parse(item.displayName)?.label
                    ?? family.label,
                subfamily: item.brewerKind?.subfamily ?? family.label,
                searchTerms: "\(item.brand) \(item.model) \(item.displayName)",
                owned: true
            )
        }
        let ownedRefs = Set(owned.compactMap(\.brewerRef))
        if family == .espresso {
            for item in ReferenceBase.kit where espressoCatalog(item) && !ownedRefs.contains(item.id) {
                entries.append(item.catalogEntry(owned: false))
            }
        } else {
            for brewer in ReferenceBase.brewers
            where BrewKit.matches(family, brewer.dripperFamily.brewerType.family)
                && !ownedRefs.contains(brewer.id)
            {
                entries.append(
                    brewer.catalogEntry(owned: false, subtitle: brewer.dripperFamily.brewerType.label)
                )
            }
            for item in ReferenceBase.kit
            where item.kind == .brewer
                && BrewKit.matches(family, item.family?.family)
                && !ownedRefs.contains(item.id)
                && ReferenceBase.brewer(id: item.id) == nil
            {
                entries.append(item.catalogEntry(owned: false))
            }
        }
        return entries
    }

    private func espressoCatalog(_ item: ReferenceBase.Item) -> Bool {
        item.kind == .espressoMachine || item.family?.family == .espresso
    }

    private var grinderEntries: [CatalogEntry] {
        var entries = setup.grinders.map { item in
            CatalogEntry(
                id: CatalogID.kit(item.id),
                title: item.displayName,
                subtitle: item.adjustment?.label ?? "Grinder",
                subfamily: item.isManual == true ? "Manual" : item.isManual == false ? "Electric" : (item.adjustment?.label ?? "Grinder"),
                searchTerms: "\(item.brand) \(item.model)",
                owned: true
            )
        }
        let ownedRefs = Set(setup.grinders.compactMap(\.grinderRef))
        for grinder in ReferenceBase.grinders where !ownedRefs.contains(grinder.id) {
            var entry = grinder.catalogEntry(owned: false)
            if let manual = grinder.isManual {
                entry.subfamily = manual ? "Manual" : "Electric"
            }
            entries.append(entry)
        }
        return entries
    }

    private var filterEntries: (items: [CatalogEntry], unmatched: Bool) {
        let result = FilterModel.filters(matching: activeBrewer)
        let owned = setup.filterStock
        var entries = owned.map { stock in
            let fits = activeBrewer.map { FilterFit.compatible(stock, with: $0) } ?? true
            return CatalogEntry(
                id: CatalogID.kit(stock.id),
                title: stock.displayName,
                subtitle: fits ? (stock.shape?.label ?? "") : Copy.notForThisDripper,
                subfamily: stock.shape?.label ?? "Paper",
                searchTerms: stock.displayName,
                owned: true
            )
        }
        let ownedModels = Set(owned.compactMap(\.modelId))
        for model in result.items where !ownedModels.contains(model.id) {
            entries.append(model.catalogEntry(owned: false))
        }
        return (entries, result.unmatched)
    }

    private var activeBrewer: Equipment? {
        BrewKit.activeBrewer(on: session.brew, in: setup)
    }

    private var selectedGrinder: Equipment? {
        session.brew.grind.grinderId.flatMap { setup.equipment(id: $0) }
            ?? setup.preferredGrinder(for: session.brew.method)
    }

    private var selectedFilter: FilterStock? {
        session.brew.filterStockId.flatMap { setup.filterStock(id: $0) }
    }

    private func applyFamily(_ family: BrewerFamily) {
        tapCount += 1
        session.apply(family: family, setup: setup)
    }

    private func pickDripper(_ entry: CatalogEntry) {
        tapCount += 1
        if let id = CatalogID.parseKit(entry.id), let item = setup.equipment(id: id) {
            assignBrewer(item)
            return
        }
        if let reference = ReferenceBase.brewer(id: entry.id) {
            let stored = setup.adopt(
                Equipment(reference: reference),
                asDefaultIfFirstFor: reference.dripperFamily.brewerType.method
            )
            assignBrewer(stored)
            return
        }
        if let item = ReferenceBase.kit.first(where: { $0.id == entry.id }) {
            let stored = setup.adopt(
                Equipment(reference: item),
                asDefaultIfFirstFor: item.family?.method ?? session.brew.method
            )
            assignBrewer(stored)
        }
    }

    private func pickGrinder(_ entry: CatalogEntry) {
        tapCount += 1
        if let id = CatalogID.parseKit(entry.id), let item = setup.equipment(id: id) {
            session.brew.grind.grinderId = item.id
            session.brew.captureSource = .typed
            return
        }
        if let reference = ReferenceBase.grinder(id: entry.id) {
            let stored = setup.adopt(
                Equipment(reference: reference),
                asDefaultIfFirstFor: session.brew.method
            )
            session.brew.grind.grinderId = stored.id
            session.brew.captureSource = .typed
        }
    }

    private func pickFilter(_ entry: CatalogEntry) {
        tapCount += 1
        if let id = CatalogID.parseKit(entry.id), let stock = setup.filterStock(id: id) {
            session.brew.filterStockId = stock.id
            session.brew.captureSource = .typed
            return
        }
        if let model = ReferenceBase.filters.first(where: { $0.id == entry.id }) {
            let existing = setup.filterStock.first { $0.modelId == model.id }
            let stock = existing ?? FilterStock(
                modelId: model.id,
                size: model.sizes.first ?? "",
                shape: model.shape
            )
            if existing == nil { setup.add(stock, defaultFor: activeBrewer?.id) }
            session.brew.filterStockId = stock.id
            session.brew.captureSource = .typed
        }
    }

    private func assignBrewer(_ item: Equipment) {
        BrewKit.assign(
            item,
            to: &session.brew,
            setup: setup,
            card: session.card,
            recipe: session.recipe
        )
    }
}

struct AppliedFromLastBlock: View {
    var change: String
    var onKeep: () -> Void
    var onUndo: () -> Void

    var body: some View {
        InsightBlock(
            title: Copy.appliedFromLastBrew,
            bodyText: change.capitalizedFirst,
            provenance: "From the move you chose"
        ) {
            HStack(spacing: 18) {
                Button("Keep", action: onKeep).catalogueLabel()
                Button("Undo", action: onUndo).catalogueLabel()
            }
        }
    }
}
