import SwiftUI

/// Setup as a flow: one entry door, then three skippable questions.
///
/// Opens after the first scan has landed. Relanched from Profile. Nothing is
/// required; closing keeps whatever was already written.
struct SetupFlowSheet: View {
    @Environment(SetupStore.self) private var setup
    @Environment(SetupFlowController.self) private var flow
    @Environment(\.dismiss) private var dismiss

    @State private var stage: Stage
    @State private var selectedFamilies: [BrewerType] = []
    @State private var pickingGrinder = false
    @State private var pickedGrinder: ReferenceBase.Grinder?
    @State private var customBrand = ""
    @State private var customModel = ""
    @State private var waterChoice: WaterSource?
    @State private var bottled: ReferenceBase.Water?
    @State private var additive: ReferenceBase.MineralProduct?
    @State private var paperChoice: PaperChoice?
    @State private var appeared = false

    private enum PaperChoice: String, CaseIterable, Identifiable {
        case brand
        case abaca
        case other

        var id: String { rawValue }

        var label: String {
            switch self {
            case .brand: "The dripper's paper"
            case .abaca: "Cafec Abaca"
            case .other: "Other"
            }
        }

        func brandLabel(for families: [BrewerType]) -> String {
            if families.contains(.v60) || families.contains(.immersionSwitch) { return "Hario" }
            if families.contains(.flat) { return "Kalita" }
            if families.contains(.chemex) { return "Chemex" }
            if families.contains(.aeropress) { return "AeroPress" }
            return "The dripper's paper"
        }
    }

    private enum Stage: Int {
        case entry
        case brew
        case grind
        case water

        var questionNumber: Int? {
            switch self {
            case .entry: nil
            case .brew: 1
            case .grind: 2
            case .water: 3
            }
        }
    }

    /// Opens one question directly. Used by the parcours export, not by the app.
    enum ExportStage {
        case entry
        case brew
        case grind
        case water
    }

    init(kitIsEmpty: Bool) {
        _stage = State(initialValue: kitIsEmpty ? .entry : .brew)
    }

    init(exportStage: ExportStage) {
        let stage: Stage = switch exportStage {
        case .entry: .entry
        case .brew: .brew
        case .grind: .grind
        case .water: .water
        }
        _stage = State(initialValue: stage)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .entry:
                    VStack(spacing: 0) {
                        header
                            .padding(.horizontal, 26)
                            .padding(.top, 14)
                        entryStep
                            .padding(.horizontal, 26)
                            .padding(.top, 28)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        footer
                            .padding(.horizontal, 26)
                            .padding(.bottom, 28)
                            .padding(.top, 12)
                    }
                case .brew:
                    StepFlow(
                        step: 0,
                        total: 3,
                        question: questionTitle,
                        onBack: { withAnimation(Motion.snappy) { stage = .entry } },
                        onClose: close,
                        onSkip: skip,
                        onNext: next
                    ) { brewStep }
                case .grind:
                    StepFlow(
                        step: 1,
                        total: 3,
                        question: questionTitle,
                        onBack: { withAnimation(Motion.snappy) { stage = .brew } },
                        onClose: close,
                        onSkip: skip,
                        onNext: next
                    ) { grindStep }
                case .water:
                    StepFlow(
                        step: 2,
                        total: 3,
                        question: questionTitle,
                        onBack: { withAnimation(Motion.snappy) { stage = .grind } },
                        onClose: close,
                        onSkip: skip,
                        nextTitle: "Done",
                        onNext: next
                    ) { waterStep }
                }
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 14)
            .onAppear { withAnimation(Motion.gentle) { appeared = true } }
            .background(Palette.paper.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(Palette.ink)
        .presentationBackground(Palette.paper)
        .presentationContentInteraction(.scrolls)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                if let number = stage.questionNumber {
                    HStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { i in
                            Rectangle()
                                .fill(i == number - 1 ? Palette.ink : Palette.hairline)
                                .frame(width: 24, height: 1)
                        }
                    }
                }
                Spacer()
            }
            Text(stage == .entry ? "Bring what you have" : questionTitle)
                .font(Typography.question)
                .foregroundStyle(Palette.ink)
        }
    }

    private var questionTitle: String {
        switch stage {
        case .entry: ""
        case .brew: "How do you brew?"
        case .grind: "What do you grind with?"
        case .water: "What water?"
        }
    }

    // MARK: - Entry

    private var entryStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            // TODO(import): PRD §6.9, brief #3 §10. The row is the place; the parser is not this lot.
            disabledRow(
                title: "Import from another app",
                subtitle: "iBrewCoffee · Beanconqueror · Filtru · CSV",
                systemImage: "arrow.down.doc"
            )
            disabledRow(
                title: "Photo of your kit",
                subtitle: "",
                systemImage: "camera"
            )
            Button {
                withAnimation(Motion.snappy) { stage = .brew }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Image(systemName: "hand.draw")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 28)
                    Text("Set up by hand")
                        .font(Typography.value)
                        .foregroundStyle(Palette.ink)
                    Spacer()
                }
                .padding(.vertical, 11)
            }
            .buttonStyle(.plain)
            Rectangle().fill(Palette.hairline).frame(height: 1)
        }
    }

    private func disabledRow(title: String, subtitle: String, systemImage: String) -> some View {
        VStack(spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 28)
                    .foregroundStyle(Palette.inkMuted)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(Typography.value)
                        .foregroundStyle(Palette.ink)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(Typography.tag)
                            .foregroundStyle(Palette.inkMuted)
                    }
                }
                Spacer()
                Text("soon")
                    .font(Typography.tag)
                    .foregroundStyle(Palette.inkMuted)
            }
            .padding(.vertical, 11)
            .opacity(0.6)
            Rectangle().fill(Palette.hairline).frame(height: 1)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Brew

    private var brewStep: some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        let paperFamilies = selectedFamilies.filter(\.usesInterchangeableFilter)
        return VStack(alignment: .leading, spacing: 22) {
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(BrewerType.allCases) { family in
                    let on = selectedFamilies.contains(family)
                    StepChoice(
                        glyph: family.glyph,
                        label: family.label,
                        isSelected: on
                    ) {
                        withAnimation(Motion.quick) {
                            if let index = selectedFamilies.firstIndex(of: family) {
                                selectedFamilies.remove(at: index)
                            } else {
                                selectedFamilies.append(family)
                            }
                            if paperFamilies.isEmpty { paperChoice = nil }
                        }
                    }
                }
            }
            if !paperFamilies.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(Copy.whichPaper).catalogueLabel()
                    ChipRail {
                        ForEach(PaperChoice.allCases) { choice in
                            TagChip(
                                text: choice == .brand
                                    ? choice.brandLabel(for: paperFamilies)
                                    : choice.label,
                                isSelected: paperChoice == choice
                            ) {
                                paperChoice = paperChoice == choice ? nil : choice
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Grind

    private var grindStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button { pickingGrinder = true } label: {
                HStack {
                    Text(pickedGrinder.map { [$0.brand, $0.model].filter { !$0.isEmpty }.joined(separator: " ") } ?? "Choose a grinder")
                        .font(Typography.value)
                        .foregroundStyle(pickedGrinder == nil ? Palette.inkMuted : Palette.ink)
                    Spacer()
                    Text(Copy.change).catalogueLabel()
                }
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)

            Button {
                pickedGrinder = nil
            } label: {
                Text("Add manually")
                    .catalogueLabel()
            }
            .buttonStyle(.plain)

            if pickedGrinder == nil {
                TextRow(label: "Brand", text: $customBrand, placeholder: Placeholders.text(.grinderBrand), presence: .useful)
                TextRow(label: "Model", text: $customModel, placeholder: Placeholders.text(.grinderModel), presence: .useful)
            }
        }
        .sheet(isPresented: $pickingGrinder) {
            CatalogPicker(
                title: "Grinder",
                entries: ReferenceBase.grinders.map { $0.catalogEntry(owned: false) },
                selectedID: pickedGrinder?.id,
                onPick: { entry in
                    pickedGrinder = ReferenceBase.grinders.first { $0.id == entry.id }
                    customBrand = ""
                    customModel = ""
                    pickingGrinder = false
                },
                onAddManually: {
                    pickingGrinder = false
                    pickedGrinder = nil
                }
            )
        }
    }

    // MARK: - Water

    private var waterStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            ChipPicker(
                items: [WaterSource.tap, .bottled, .recipe],
                label: \.label,
                selection: $waterChoice,
                allowsDeselect: true
            )

            if waterChoice == .bottled {
                ChipRail {
                    ForEach(ReferenceBase.waters) { water in
                        TagChip(text: water.name, isSelected: bottled?.id == water.id) {
                            bottled = bottled?.id == water.id ? nil : water
                        }
                    }
                }
            }

            if waterChoice == .recipe {
                ChipRail {
                    ForEach(ReferenceBase.mineralProducts) { product in
                        TagChip(text: product.name, isSelected: additive?.id == product.id) {
                            additive = additive?.id == product.id ? nil : product
                        }
                    }
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Skip") { skip() }
                .catalogueLabel()
            Spacer()
            if stage != .entry {
                Button("Next") { next() }
                    .catalogueLabel()
                    .foregroundStyle(Palette.ink)
            }
        }
    }

    private func skip() {
        switch stage {
        case .entry:
            close()
        case .brew:
            withAnimation(Motion.snappy) { stage = .grind }
        case .grind:
            withAnimation(Motion.snappy) { stage = .water }
        case .water:
            close()
        }
    }

    private func next() {
        switch stage {
        case .entry:
            withAnimation(Motion.snappy) { stage = .brew }
        case .brew:
            commitBrewers()
            withAnimation(Motion.snappy) { stage = .grind }
        case .grind:
            commitGrinder()
            withAnimation(Motion.snappy) { stage = .water }
        case .water:
            commitWater()
            close()
        }
    }

    private func commitBrewers() {
        guard !selectedFamilies.isEmpty else { return }
        if let first = selectedFamilies.first {
            setup.setPreferredRecipeMethod(first.method)
        }
        for family in selectedFamilies {
            var item = Equipment(
                kind: family.equipmentKind,
                brand: "",
                model: family.label,
                brewerType: family.storageValue
            )
            if family == .espresso {
                item.kind = .espressoMachine
            }
            setup.add(item)
            setup.setDefault(item, for: family.method, on: true)
            commitPaper(for: item, family: family)
        }
    }

    private func commitPaper(for brewer: Equipment, family: BrewerType) {
        guard family.usesInterchangeableFilter, let paperChoice, paperChoice != .other else { return }
        let modelId: String?
        let size: String
        switch (paperChoice, family) {
        case (.abaca, _):
            modelId = "cafec-abaca"
            size = family == .flat ? "185" : "4cup"
        case (.brand, .flat):
            modelId = "kalita-wave-185"
            size = "185"
        case (.brand, .chemex):
            modelId = "chemex-bonded-white"
            size = "6cup"
        case (.brand, .aeropress):
            modelId = "aeropress-paper"
            size = "60mm"
        default:
            modelId = "hario-v60-white-jp-tabbed"
            size = "02"
        }
        let stock = FilterStock(
            modelId: modelId,
            size: size,
            shape: ReferenceBase.filters.first { $0.id == modelId }?.shape
        )
        setup.add(stock, defaultFor: brewer.id)
    }

    private func commitGrinder() {
        let item: Equipment
        if let pickedGrinder {
            item = Equipment(reference: pickedGrinder)
        } else {
            let brand = customBrand.trimmingCharacters(in: .whitespaces)
            let model = customModel.trimmingCharacters(in: .whitespaces)
            guard !brand.isEmpty || !model.isEmpty else { return }
            item = Equipment(kind: .grinder, brand: brand, model: model, adjustment: .clicks)
        }
        setup.add(item)
        let methods = selectedFamilies.map(\.method)
        let targets = methods.isEmpty ? BrewMethod.allCases : Array(Set(methods))
        for method in targets {
            setup.setDefault(item, for: method, on: true)
        }
    }

    private func commitWater() {
        guard let waterChoice else { return }
        var profile: WaterProfile
        switch waterChoice {
        case .tap, .filtered:
            profile = WaterProfile(name: "Tap", source: .tap)
        case .bottled:
            if let bottled {
                profile = WaterProfile(reference: bottled)
            } else {
                profile = WaterProfile(name: "Bottled", source: .bottled)
            }
        case .recipe:
            profile = WaterProfile(
                name: additive?.name ?? "Recipe",
                source: .recipe,
                additiveName: additive?.name,
                additiveDose: additive?.dose
            )
        }
        profile.isDefault = true
        setup.add(profile)
        setup.makeDefault(profile)
    }

    private func close() {
        flow.dismissed()
        dismiss()
    }
}
