import SwiftUI

/// The cupboard, the tap, and the account — one paper sheet.
///
/// No Angusta title. The first label is YOUR KIT. Account is a row that opens
/// the existing system List, and only when Supabase is configured.
struct ProfileSheet: View {
    @Environment(SetupStore.self) private var setup
    @Environment(LotFlags.self) private var lotFlags
    @Environment(AIFlags.self) private var flags
    @Environment(AIEventLog.self) private var aiEvents
    @Environment(AccountStore.self) private var account
    @Environment(SetupFlowController.self) private var flow
    @Environment(\.appEnvironment) private var appEnvironment
    @Environment(\.dismiss) private var dismiss

    @State private var editing: Equipment?
    @State private var addingKind: EquipmentKind?
    @State private var editingWater: WaterProfile?
    @State private var isAddingWater = false
    @State private var isConverting = false
    @State private var isShowingAccount = false
    @State private var isShowingFlow = false
    @State private var confirmResetKit = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 34) {
                    kitSection
                    waterSection
                    defaultsSection
                    grindSection
                    setUpAgainSection
                    #if DEBUG
                    developerSection
                    #endif
                    importExportSection
                    flagsSection
                    experimentalSection
                    if account.isAvailable {
                        accountRow
                    }
                }
                .padding(.horizontal, 26)
                .padding(.top, 16)
                .padding(.bottom, 48)
            }
            .scrollIndicators(.hidden)
            .background(Palette.paper.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.medium)
                }
            }
        }
        .tint(Palette.ink)
        .sheet(item: $editing) { item in
            EquipmentSheet(equipment: item)
                .appEnvironment(appEnvironment)
        }
        .sheet(item: $addingKind) { kind in
            EquipmentSheet(kind: kind)
                .appEnvironment(appEnvironment)
        }
        .sheet(item: $editingWater) { profile in
            WaterSheet(profile: profile)
                .appEnvironment(appEnvironment)
        }
        .sheet(isPresented: $isAddingWater) {
            WaterSheet(profile: nil)
                .appEnvironment(appEnvironment)
        }
        .sheet(isPresented: $isConverting) {
            GrindConverterSheet()
                .appEnvironment(appEnvironment)
        }
        .sheet(isPresented: $isShowingAccount) {
            AccountSheet()
                .appEnvironment(appEnvironment)
        }
        .sheet(isPresented: $isShowingFlow, onDismiss: { flow.dismissed() }) {
            SetupFlowSheet(kitIsEmpty: setup.kitIsEmpty)
                .appEnvironment(appEnvironment)
        }
        .confirmationDialog("Reset kit?", isPresented: $confirmResetKit, titleVisibility: .visible) {
            Button("Reset kit", role: .destructive) { setup.resetKit() }
        }
    }

    // MARK: - Kit

    private var kitSection: some View {
        SetupSection(title: "Your kit", waiting: "", isEmpty: false) {
            VStack(spacing: 8) {
                ForEach(EquipmentKind.allCases) { kind in
                    let items = setup.equipment(kind)
                    VStack(spacing: 0) {
                        ForEach(items) { item in
                            KitRow(
                                item: item,
                                onTap: { editing = item },
                                onRemove: { setup.delete(item) }
                            )
                        }
                        SetupAddRow(title: "Add a \(kind.label.lowercased())") {
                            addingKind = kind
                        }
                    }
                }
                disabledSoonRow(
                    title: "Add from a photo",
                    systemImage: "camera"
                )
            }
        }
    }

    private var waterSection: some View {
        SetupSection(
            title: "Water",
            waiting: "98 % of the cup, and the one thing nobody logs",
            isEmpty: setup.waterProfiles.isEmpty
        ) {
            VStack(spacing: 0) {
                ForEach(setup.waterProfiles) { profile in
                    WaterKitRow(profile: profile) { editingWater = profile }
                }
                SetupAddRow(title: "Add water") { isAddingWater = true }
            }
        }
    }

    private var defaultsSection: some View {
        SetupSection(
            title: "Defaults",
            waiting: "Mark a grinder or brewer as default for a method",
            isEmpty: methodsWithDefaults.isEmpty
        ) {
            VStack(spacing: 11) {
                ForEach(methodsWithDefaults) { method in
                    let items = setup.defaults(for: method)
                    SetupRow(
                        title: method.label,
                        tag: items.map(\.displayName).joined(separator: " · ")
                    ) {
                        editing = items.first
                    }
                }
            }
        }
    }

    private var methodsWithDefaults: [BrewMethod] {
        BrewMethod.allCases.filter { !setup.defaults(for: $0).isEmpty }
    }

    private var grindSection: some View {
        SetupSection(
            title: "Grind",
            waiting: "Add a grinder to convert settings between them",
            isEmpty: setup.grinders.isEmpty
        ) {
            VStack(spacing: 11) {
                if !setup.grinders.isEmpty {
                    SetupRow(
                        title: "Convert a setting",
                        detail: converterDetail,
                        tag: setup.calibrations.isEmpty
                            ? "no calibration yet"
                            : "\(setup.calibrations.count) calibrated"
                    ) {
                        isConverting = true
                    }
                }
            }
        }
    }

    private var converterDetail: String {
        guard setup.grinders.count >= 2 else {
            return "One grinder on file — a second makes this useful"
        }
        return setup.grinders.map(\.displayName).joined(separator: " ")
    }

    private var setUpAgainSection: some View {
        SetupSection(title: "Set up again", waiting: "", isEmpty: false) {
            Button {
                isShowingFlow = true
            } label: {
                HStack {
                    Text("Set up again")
                        .font(Typography.value)
                        .foregroundStyle(Palette.ink)
                    Spacer()
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        }
    }

    #if DEBUG
    private var developerSection: some View {
        SetupSection(title: "Developer", waiting: "", isEmpty: false) {
            VStack(alignment: .leading, spacing: 14) {
                Button("Run onboarding") { isShowingFlow = true }
                Button("Reset first-scan flag") { flow.resetFirstScanFlag() }
                Button("Reset kit") { confirmResetKit = true }
            }
            .font(Typography.tag)
            .foregroundStyle(Palette.inkMuted)
        }
    }
    #endif

    private var importExportSection: some View {
        SetupSection(title: "Import & export", waiting: "", isEmpty: false) {
            VStack(spacing: 0) {
                // TODO(import): PRD §6.9, brief #3 §10.
                disabledSoonRow(
                    title: "Import from iBrewCoffee",
                    systemImage: "arrow.down.doc"
                )
                disabledSoonRow(
                    title: "Export my archive",
                    systemImage: "square.and.arrow.up"
                )
            }
        }
    }

    private func disabledSoonRow(title: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Palette.inkMuted)
            Text(title)
                .font(Typography.value)
                .foregroundStyle(Palette.ink)
            Spacer()
            Text("soon")
                .font(Typography.tag)
                .foregroundStyle(Palette.inkMuted)
        }
        .padding(.vertical, 11)
        .opacity(0.6)
        .allowsHitTesting(false)
    }

    private var flagsSection: some View {
        SetupSection(title: Copy.features, waiting: "", isEmpty: false) {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(LotFlags.Feature.allCases) { feature in
                    flagRow(feature)
                }
            }
        }
    }

    private func flagRow(_ feature: LotFlags.Feature) -> some View {
        let on = lotFlags.isOn(feature)
        return Button {
            lotFlags.setOn(feature, !on)
            if feature == .flavorOrigin {
                BrewDiagnosis.useFlavorOrigin = lotFlags.isOn(.flavorOrigin)
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(feature.label)
                        .font(Typography.value)
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    Text(on ? "On" : "Off")
                        .font(Typography.tag)
                        .foregroundStyle(on ? Palette.ink : Palette.inkMuted)
                }
                Text(feature.fallback)
                    .font(Typography.tag)
                    .foregroundStyle(Palette.inkMuted)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private var experimentalSection: some View {
        SetupSection(title: "Experimental AI", waiting: "", isEmpty: false) {
            VStack(alignment: .leading, spacing: 16) {
                Button {
                    flags.isExperimentalEnabled.toggle()
                } label: {
                    HStack {
                        Text("Experimental AI")
                            .font(Typography.value)
                            .foregroundStyle(Palette.ink)
                        Spacer()
                        Text(flags.isExperimentalEnabled ? "On" : "Off")
                            .font(Typography.tag)
                            .foregroundStyle(flags.isExperimentalEnabled ? Palette.ink : Palette.inkMuted)
                    }
                }
                .buttonStyle(.plain)

                ForEach(AIFeature.allCases) { feature in
                    if !feature.isExperimental || flags.isExperimentalEnabled {
                        featureRow(feature)
                    }
                }

                if let line = aiEvents.acceptanceLine {
                    HStack {
                        Text("Kept")
                            .font(Typography.value)
                            .foregroundStyle(Palette.ink)
                        Spacer()
                        Text(line)
                            .font(Typography.tag)
                            .foregroundStyle(Palette.inkMuted)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func featureRow(_ feature: AIFeature) -> some View {
        let paused = flags.reason(feature) == "Paused"
        Button {
            guard !paused else { return }
            flags.setOn(feature, !flags.isOn(feature))
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(feature.label)
                        .font(Typography.value)
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    Text(flags.isOn(feature) ? "On" : "Off")
                        .font(Typography.tag)
                        .foregroundStyle(flags.isOn(feature) ? Palette.ink : Palette.inkMuted)
                }
                Text(paused ? "Paused for everyone right now." : feature.fallback)
                    .font(Typography.tag)
                    .foregroundStyle(Palette.inkMuted)
            }
        }
        .buttonStyle(.plain)
        .disabled(paused)
    }

    private var accountRow: some View {
        SetupSection(title: "Account", waiting: "", isEmpty: false) {
            Button { isShowingAccount = true } label: {
                HStack {
                    Text(account.isSignedIn ? "Signed in" : "Sign in")
                        .font(Typography.value)
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Palette.inkMuted)
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        }
    }
}
