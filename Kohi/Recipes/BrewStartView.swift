import SwiftUI

/// The first question when this coffee already has a brew.
struct BrewStartView: View {
    @Bindable var session: BrewSession
    var onBack: () -> Void
    var onClose: () -> Void

    @Environment(SetupStore.self) private var setup

    var body: some View {
        StepFlow(
            step: session.progressIndex,
            total: session.progressTotal,
            question: Copy.startABrew,
            onBack: onBack,
            onClose: onClose
        ) {
            VStack(alignment: .leading, spacing: 22) {
                if let last = session.card.brews.first {
                    choice(
                        systemName: "cup.and.saucer",
                        title: Copy.repeatLast,
                        detail: summary(last)
                    ) {
                        session.repeatLast(in: setup)
                    }
                }
                choice(
                    systemName: "list.bullet",
                    title: Copy.choosePreviousBrew,
                    detail: "This coffee"
                ) {
                    session.openPrevious()
                }
                choice(
                    systemName: "book",
                    title: Copy.useSavedRecipe,
                    detail: "Mine"
                ) {
                    session.openRecipes(.mine)
                }
                choice(
                    systemName: "plus",
                    title: Copy.startFromScratch,
                    detail: Copy.fromThePros
                ) {
                    session.openRecipes(.pros)
                }
            }
            .padding(.bottom, 24)
        }
    }

    private func choice(
        systemName: String,
        title: String,
        detail: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(Palette.hairline, lineWidth: 1)
                        .frame(width: 44, height: 44)
                    Image(systemName: systemName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Palette.ink)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Typography.value)
                        .foregroundStyle(Palette.ink)
                    Text(detail)
                        .font(Typography.tag)
                        .foregroundStyle(Palette.inkMuted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func summary(_ brew: Brew) -> String {
        var parts = [CatalogueDate.happened(brew.date)]
        if let method = brew.method { parts.append(method.label) }
        if let dose = brew.dose { parts.append("\(GrindRange.number(dose)) g") }
        if let ratio = brew.ratio { parts.append(ratio) }
        return parts.joined(separator: " · ")
    }
}

/// Brews already logged on this coffee. Choosing one opens How much? with its numbers.
struct BrewPreviousView: View {
    @Bindable var session: BrewSession
    var onBack: () -> Void
    var onClose: () -> Void

    @Environment(SetupStore.self) private var setup

    var body: some View {
        StepFlow(
            step: session.progressIndex,
            total: session.progressTotal,
            question: Copy.previousBrews,
            onBack: onBack,
            onClose: onClose
        ) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(session.card.brews) { brew in
                    Button {
                        session.repeatBrew(brew, setup: setup)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(title(brew))
                                .font(Typography.value)
                                .foregroundStyle(Palette.ink)
                                .lineLimit(1)
                            Text(detail(brew))
                                .font(Typography.tag)
                                .foregroundStyle(Palette.inkMuted)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    Rectangle().fill(Palette.hairline).frame(height: 1)
                }
            }
            .padding(.bottom, 24)
        }
    }

    private func title(_ brew: Brew) -> String {
        var parts = [CatalogueDate.happened(brew.date)]
        if let method = brew.method { parts.append(method.label) }
        if let name = brewerName(brew) { parts.append(name) }
        return parts.joined(separator: " · ")
    }

    private func detail(_ brew: Brew) -> String {
        var parts: [String] = []
        if let dose = brew.dose { parts.append("\(GrindRange.number(dose)) g") }
        if let ratio = brew.ratio { parts.append(ratio) }
        if let temperature = brew.temperature {
            parts.append("\(GrindRange.number(temperature)) °C")
        }
        return parts.joined(separator: " · ")
    }

    private func brewerName(_ brew: Brew) -> String? {
        brew.equipmentIDs
            .compactMap { setup.equipment(id: $0) }
            .first { BrewKit.isCupboard($0.kind) }?
            .displayName
    }
}
