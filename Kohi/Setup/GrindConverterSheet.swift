import SwiftUI

/// "What is 22 clicks on my Comandante, on the J-Ultra?"
///
/// One row of the Setup sheet, and the place where the honesty of the whole
/// conversion is on display: the answer always carries what it rests on, and
/// when that is a published range rather than your own calibration, it says so
/// in the same breath as the number.
struct GrindConverterSheet: View {
    @Environment(SetupStore.self) private var setup
    @Environment(\.appEnvironment) private var appEnvironment
    @Environment(\.dismiss) private var dismiss

    @State private var sourceID: UUID?
    @State private var targetID: UUID?
    @State private var method: BrewMethod? = .v60
    @State private var setting: Double?
    @State private var isCalibrating = false
    @State private var showCatalog = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if setup.grinders.count < 2 {
                        needsTwoGrinders
                        Button("Browse catalogue") { showCatalog = true }
                            .catalogueLabel()
                    } else {
                        pickers
                        result
                        calibrationSection
                    }

                    publishedTable
                    explanation
                }
                .padding(.horizontal, 26)
                .padding(.top, 16)
                .padding(.bottom, 44)
            }
            .scrollIndicators(.hidden)
            .background(Palette.paper.ignoresSafeArea())
            .navigationTitle("Grind")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.medium)
                }
            }
        }
        .tint(Palette.ink)
        .onAppear(perform: preselect)
        .sheet(isPresented: $showCatalog) {
            CatalogPicker(
                title: "Grinder",
                entries: ReferenceBase.grinders.map { $0.catalogEntry(owned: false) },
                selectedID: nil,
                onPick: { entry in
                    if let grinder = ReferenceBase.grinder(id: entry.id) {
                        setup.add(Equipment(reference: grinder))
                    }
                    showCatalog = false
                },
                onAddManually: { showCatalog = false }
            )
        }
        .sheet(isPresented: $isCalibrating) {
            if let target {
                CalibrationSheet(grinder: target, method: method ?? .v60)
                    .appEnvironment(appEnvironment)
            }
        }
    }

    private var source: Equipment? { sourceID.flatMap { setup.equipment(id: $0) } }
    private var target: Equipment? { targetID.flatMap { setup.equipment(id: $0) } }

    private func preselect() {
        guard sourceID == nil else { return }
        sourceID = setup.grinders.first?.id
        targetID = setup.grinders.dropFirst().first?.id
    }

    // MARK: - Sections

    private var needsTwoGrinders: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Two grinders needed")
                .catalogueLabel()
            Text("""
            A conversion needs something to convert between. Add a second \
            grinder — the one on the recipe, or the one at the roastery — and \
            this becomes useful.
            """)
            .font(Typography.tag)
            .foregroundStyle(Palette.inkMuted)
        }
    }

    private var pickers: some View {
        VStack(alignment: .leading, spacing: 16) {
            FormField(label: "From") {
                ChipPicker(
                    items: setup.grinders,
                    label: \.displayName,
                    selection: Binding(
                        get: { source },
                        set: { sourceID = $0?.id }
                    ),
                    allowsDeselect: false
                )
            }

            NumberRow("Setting", value: $setting, unit: settingUnit)

            FormField(label: "To") {
                ChipPicker(
                    items: setup.grinders,
                    label: \.displayName,
                    selection: Binding(
                        get: { target },
                        set: { targetID = $0?.id }
                    ),
                    allowsDeselect: false
                )
            }

            FormField(label: "Method") {
                ChipPicker(
                    items: BrewMethod.allCases,
                    label: \.label,
                    selection: $method,
                    allowsDeselect: false
                )
            }
        }
    }

    private var settingUnit: String {
        switch source?.adjustment {
        case .clicks: "clicks"
        case .dial: "on the dial"
        case .stepless, .none: ""
        }
    }

    /// The answer, or a plain statement of what is missing. A conversion with
    /// no basis returns nothing rather than a plausible number.
    @ViewBuilder
    private var result: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("On your \(target?.displayName ?? "grinder")")
                .catalogueLabel()

            if let translation {
                Text(translation.label)
                    .font(Typography.title)
                    .foregroundStyle(Palette.ink)
                Text(basisLine(translation))
                    .font(Typography.tag)
                    .foregroundStyle(Palette.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(missingLine)
                    .font(Typography.tag)
                    .foregroundStyle(Palette.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Rectangle().fill(Palette.hairline).frame(height: 1)
        }
        .animation(Motion.snappy, value: translation)
    }

    private var translation: GrindTranslation? {
        guard let source, let target, let setting, let method else { return nil }
        return GrindConversion.translate(
            setting: setting,
            method: method,
            from: source,
            to: target,
            calibrations: setup.calibrations
        )
    }

    private func basisLine(_ translation: GrindTranslation) -> String {
        var line = translation.basis.label.capitalizedFirst
        if translation.wasClamped {
            line += ", pulled back to the edge of your declared range"
        }
        if !translation.basis.isYours {
            line += ". Calibrate it below and this becomes a measurement."
        }
        return line
    }

    private var missingLine: String {
        guard setting != nil else { return "Enter a setting to convert." }
        guard let method else { return "Pick a method." }
        let missing = [source, target]
            .compactMap { $0 }
            .filter { GrindConversion.range(for: method, on: $0) == nil }
            .map(\.displayName)
        guard !missing.isEmpty else { return "Nothing to go on yet." }
        return """
        No range declared for \(method.label) on \(missing.joined(separator: " or ")). \
        Set one in Setup — "my V60 is 20 to 26" — and the conversion has \
        something real to work from.
        """
    }

    private var calibrationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Calibration")
                .catalogueLabel()

            if let target, let method,
               let existing = setup.calibration(grinderID: target.id, method: method) {
                HStack(alignment: .firstTextBaseline) {
                    Text(existing.summary)
                        .font(Typography.value)
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    Button("Change") { isCalibrating = true }
                        .font(Typography.tag)
                        .foregroundStyle(Palette.inkMuted)
                }
            } else {
                Button("Set my reference for this method") { isCalibrating = true }
                    .font(Typography.tag)
                    .foregroundStyle(Palette.ink)
            }
        }
    }

    private var publishedTable: some View {
        let brewMethod = method ?? .v60
        let rows: [(id: String, name: String, low: Double, high: Double, caption: String)] =
            setup.grinders.compactMap { grinder in
                guard let row = PublishedGrindRanges.match(grinderRef: grinder.grinderRef, method: brewMethod),
                      let caption = PublishedGrindRanges.caption(grinderRef: grinder.grinderRef, method: brewMethod)
                else { return nil }
                return (grinder.id.uuidString, grinder.displayName, row.min, row.max, caption)
            }
        return VStack(alignment: .leading, spacing: 10) {
            Text("Published ranges")
                .catalogueLabel()
            if rows.isEmpty {
                Text("No published range on file for \(brewMethod.label). Log your range and it takes over.")
                    .font(Typography.tag)
                    .foregroundStyle(Palette.inkMuted)
            } else {
                ForEach(rows, id: \.id) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(row.name)
                            .font(Typography.value)
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text("\(GrindRange.number(row.low))–\(GrindRange.number(row.high))")
                            .font(Typography.tag)
                            .foregroundStyle(Palette.inkMuted)
                    }
                    Text(row.caption)
                        .font(Typography.tag)
                        .foregroundStyle(Palette.inkMuted)
                }
            }
            Text(Copy.publishedRangesWarning)
                .font(Typography.tag)
                .foregroundStyle(Palette.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var explanation: some View {
        Text("""
        Every number here is approximate, and the app will keep saying so. \
        Maker step sizes measure how far the burr moves, not how big the \
        grounds are, and published ranges are what people tend to do. A \
        calibration of your own is the only figure that comes from coffee.
        """)
        .font(Typography.tag)
        .foregroundStyle(Palette.inkMuted)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// "My 22 clicks is my V60 reference." One number, one method, one grinder.
struct CalibrationSheet: View {
    let grinder: Equipment
    let method: BrewMethod

    @Environment(SetupStore.self) private var setup
    @Environment(\.dismiss) private var dismiss

    @State private var setting: Double?
    @State private var microns: Double?
    @State private var note = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(spacing: 16) {
                        NumberRow("Setting", value: $setting, unit: unit)
                        NumberRow("Is about", value: $microns, unit: "µm")
                        TextRow(
                            label: "Note",
                            text: $note,
                            placeholder: "where the number came from",
                            capitalization: .sentences
                        )
                        DictationField(text: $note)
                    }

                    Text("""
                    The microns are optional and only worth filling in if you \
                    have a basis for them — a sieve, a published measurement, a \
                    shop's readout. Without them, the setting alone still \
                    anchors every conversion for \(method.label) on this \
                    grinder, which is most of the value.
                    """)
                    .font(Typography.tag)
                    .foregroundStyle(Palette.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 26)
                .padding(.top, 14)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .background(Palette.paper.ignoresSafeArea())
            .navigationTitle("\(method.label) reference")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.medium)
                        .disabled(setting == nil)
                }
            }
        }
        .tint(Palette.ink)
        .onAppear {
            guard let existing = setup.calibration(grinderID: grinder.id, method: method) else {
                return
            }
            setting = existing.setting
            microns = existing.micronsProxy
            note = existing.note
        }
    }

    private var unit: String {
        switch grinder.adjustment {
        case .clicks: "clicks"
        case .dial: "on the dial"
        case .stepless, .none: ""
        }
    }

    private func save() {
        guard let setting else { return }
        let existing = setup.calibration(grinderID: grinder.id, method: method)
        setup.record(GrindCalibration(
            id: existing?.id ?? UUID(),
            grinderID: grinder.id,
            method: method,
            setting: setting,
            micronsProxy: microns,
            note: note,
            createdAt: existing?.createdAt ?? .now
        ))
        dismiss()
    }
}
