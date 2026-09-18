import SwiftUI

/// Method, kettle, water, grinder — the kit the recipe path used to skip.
struct BrewKitView: View {
    @Bindable var session: BrewSession
    var onBack: () -> Void
    var onClose: () -> Void
    var onBrewNow: () -> Void
    var onAlreadyBrewed: () -> Void

    @Environment(SetupStore.self) private var setup
    @Environment(\.appEnvironment) private var appEnvironment

    @State private var tapCount = 0
    @State private var showProfile = false
    @State private var fieldFocused = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 26)
                .padding(.top, 14)

            Text("With what?")
                .font(Typography.question)
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 26)
                .padding(.top, 28)

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    methodSection
                    kettleRow
                    waterSection
                    grindRow
                    temperatureRow
                    agitationRow
                    filterRow
                    Button("Edit kit") { showProfile = true }
                        .catalogueLabel()
                }
                .padding(.horizontal, 26)
                .padding(.top, 22)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .fieldKeyboardClearance()

            if !fieldFocused {
                footer
                    .padding(.horizontal, 26)
                    .padding(.bottom, 28)
                    .padding(.top, 12)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .background(Palette.paper.ignoresSafeArea())
        .onPreferenceChange(FieldFocusPreference.self) { fieldFocused = $0 }
        .animation(Motion.snappy, value: fieldFocused)
        .haptic(.tap, trigger: tapCount)
        .sheet(isPresented: $showProfile) {
            if let appEnvironment {
                ProfileSheet().appEnvironment(appEnvironment)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .touchTarget()
            }
            .buttonStyle(.plain)

            HStack(spacing: 4) {
                ForEach(0..<session.progressTotal, id: \.self) { index in
                    Rectangle()
                        .fill(index == 1 ? Palette.ink : Palette.hairline)
                        .frame(width: 24, height: 1)
                }
            }
            Spacer(minLength: 8)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.inkMuted)
                    .touchTarget()
            }
            .buttonStyle(.plain)
        }
    }

    private var footer: some View {
        VStack(spacing: 12) {
            if session.mode == .edit {
                Button {
                    session.alreadyBrewed()
                } label: {
                    Text("After")
                        .font(Typography.label)
                        .tracking(Typography.labelTracking)
                        .textCase(.uppercase)
                        .foregroundStyle(Palette.paper)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Palette.ink, in: Capsule())
                }
                .buttonStyle(.plain)
            } else {
                Button(action: onBrewNow) {
                    Text("Brew now")
                        .font(Typography.label)
                        .tracking(Typography.labelTracking)
                        .textCase(.uppercase)
                        .foregroundStyle(Palette.paper)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Palette.ink, in: Capsule())
                }
                .buttonStyle(.plain)

                Button("Already brewed", action: onAlreadyBrewed)
                    .catalogueLabel()
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
            }
        }
    }

    private var methodSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Method").catalogueLabel()
            FlowLayout {
                ForEach(BrewMethod.allCases) { method in
                    TagChip(
                        text: method.label,
                        isSelected: session.brew.method == method
                    ) {
                        tapCount += 1
                        let picked = session.brew.method == method ? nil : method
                        session.apply(method: picked, setup: setup)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var kettleRow: some View {
        let kettles = setup.equipment(.kettle)
        VStack(alignment: .leading, spacing: 12) {
            Text("Kettle").catalogueLabel()
            if kettles.isEmpty {
                Text("Add a kettle in Setup")
                    .font(Typography.tag)
                    .foregroundStyle(Palette.inkMuted)
            } else {
                ChipToggles(
                    items: kettles,
                    label: \.displayName,
                    isOn: { session.brew.equipmentIDs.contains($0.id) },
                    toggle: toggleEquipment
                )
            }
            let brewers = setup.equipment(.brewer)
            if !brewers.isEmpty {
                Text("Brewer").catalogueLabel()
                    .padding(.top, 8)
                ChipToggles(
                    items: brewers,
                    label: \.displayName,
                    isOn: { session.brew.equipmentIDs.contains($0.id) },
                    toggle: toggleEquipment
                )
            }
        }
    }

    private var waterSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Water").catalogueLabel()
            if setup.waterProfiles.isEmpty {
                Text("Add water in Setup")
                    .font(Typography.tag)
                    .foregroundStyle(Palette.inkMuted)
            } else {
                ChipPicker(
                    items: setup.waterProfiles,
                    label: \.displayName,
                    selection: Binding(
                        get: { session.brew.waterProfileID.flatMap { setup.waterProfile(id: $0) } },
                        set: { session.brew.waterProfileID = $0?.id }
                    ),
                    onPick: { tapCount += 1 }
                )
            }
        }
    }

    private var grindRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Grind").catalogueLabel()
            if setup.grinders.isEmpty {
                Text("Add a grinder in Setup")
                    .font(Typography.tag)
                    .foregroundStyle(Palette.inkMuted)
            } else {
                ChipPicker(
                    items: setup.grinders,
                    label: \.displayName,
                    selection: grinderBinding,
                    allowsDeselect: false,
                    onPick: { tapCount += 1 }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            GrindRail(
                setting: $session.brew.grind,
                grinder: selectedGrinder,
                method: session.brew.method,
                onChange: { tapCount += 1 }
            )
            if let microns = session.brew.grind.micronsLabel(
                grinder: selectedGrinder,
                calibrations: setup.calibrations,
                method: session.brew.method
            ) {
                DerivedValue(text: microns, empty: "")
            }
        }
    }

    private var selectedGrinder: Equipment? {
        session.brew.grind.grinderId.flatMap { setup.equipment(id: $0) }
            ?? setup.preferredGrinder(for: session.brew.method)
    }

    private var grinderBinding: Binding<Equipment?> {
        Binding(
            get: { selectedGrinder },
            set: { pickGrinder($0) }
        )
    }

    private func pickGrinder(_ next: Equipment?) {
        guard let next else {
            session.brew.grind.grinderId = nil
            return
        }
        if let current = selectedGrinder,
           current.id != next.id,
           let value = session.brew.grind.value,
           let method = session.brew.method,
           let translated = GrindConversion.translate(
               setting: value,
               method: method,
               from: current,
               to: next,
               calibrations: setup.calibrations
           )
        {
            session.brew.grind = GrindSetting(
                grinderId: next.id,
                value: translated.setting,
                raw: session.brew.grind.raw
            )
        } else {
            session.brew.grind.grinderId = next.id
        }
    }

    private var temperatureRow: some View {
        NumberRow(
            "Temp",
            value: $session.brew.temperature,
            unit: "°C",
            placeholder: Placeholders.text(.brewTemperature),
            labelWidth: 74,
            hint: temperatureHint,
            error: session.brew.temperature.flatMap(FieldCopy.boiling)
        )
    }

    private var temperatureHint: String? {
        guard session.brew.temperature == nil, let method = session.brew.method else { return nil }
        let band = RecipeRules.temperature(for: session.card.roastLevel, method: method)
        let roast = session.card.roastLevel?.label.lowercased() ?? "unknown roast"
        return "\(GrindRange.number(band.lowerBound))–\(GrindRange.number(band.upperBound)) °C for a \(roast) roast"
    }

    private var agitationRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Agitation").catalogueLabel()
            ChipPicker(
                items: Array(Agitation.allCases),
                label: \.label,
                selection: $session.brew.agitation,
                onPick: { tapCount += 1 }
            )
        }
    }

    private var filterRow: some View {
        let filters = activeBrewer?.filters.filter { !$0.isEmpty } ?? []
        return VStack(alignment: .leading, spacing: 10) {
            Text("Filter").catalogueLabel()
            if filters.isEmpty {
                Text(activeBrewer == nil ? "Pick a brewer" : "Add filters in Profile")
                    .font(Typography.tag)
                    .foregroundStyle(Palette.inkMuted)
            } else {
                ChipPicker(
                    items: filters,
                    label: \.displayName,
                    selection: Binding(
                        get: { filters.first { $0.id == session.brew.filterId } },
                        set: { session.brew.filterId = $0?.id }
                    ),
                    onPick: { tapCount += 1 }
                )
            }
        }
    }

    private var activeBrewer: Equipment? {
        session.brew.equipmentIDs.compactMap { setup.equipment(id: $0) }.first { $0.kind == .brewer }
    }

    private func toggleEquipment(_ item: Equipment, on: Bool) {
        tapCount += 1
        if on {
            session.brew.equipmentIDs.append(item.id)
        } else {
            session.brew.equipmentIDs.removeAll { $0 == item.id }
        }
    }
}
