import SwiftUI

/// The Kohi card full screen, with the symbol treatments and the layout side by side.
/// Nothing is written until Done, except Redo, which measures the pack again.
struct SymbolEditorView: View {
    let card: CoffeeCard

    @Environment(CardLookStore.self) private var looks
    @Environment(StampLibrary.self) private var stamps
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale

    @State private var style: SymbolStyle = .auto
    @State private var layout: CardLayout = .label
    @State private var large: [SymbolTreatment: CardBackdrop.Rendered] = [:]
    @State private var thumbs: [SymbolTreatment: CGImage] = [:]
    @State private var renderedRevision = -1
    @State private var isRedoing = false
    @State private var redoOutcome: String?
    @State private var tilt = DeviceTilt()

    private static let thumbWidth: CGFloat = 64

    var body: some View {
        GeometryReader { proxy in
            let width = min(proxy.size.width - 48, (proxy.size.height - 260) * CardTileLayout.aspectRatio)
            VStack(spacing: 0) {
                header
                Spacer(minLength: 12)
                stage(width: max(160, width))
                Spacer(minLength: 12)
                controls
            }
        }
        .background(Palette.paper.ignoresSafeArea())
        .onAppear {
            style = stamps.style(for: card.id)
            layout = looks.layout(for: card.id)
        }
        .task(id: stamps.revision(for: card.id)) { await renderAll() }
        .onChange(of: treatment) { _, next in
            next == .emboss ? tilt.start() : tilt.stop()
        }
        .onDisappear { tilt.stop() }
    }

    // MARK: - Pieces

    private var header: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .catalogueLabel()
                .foregroundStyle(Palette.inkMuted)
            Spacer()
            Button("Done") { save() }
                .catalogueLabel()
                .foregroundStyle(Palette.ink)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
        .padding(.top, 12)
    }

    private func stage(width: CGFloat) -> some View {
        let art = CardArt.make(card, ink: file)
        let rendered = large[treatment]
        let waiting = rendered == nil ? CardComposer.shared.placeholderField(for: card) : nil
        return KohiCard(
            content: KohiCardContent.make(card, art: art),
            density: .detail,
            width: width,
            layout: layout,
            backdrop: rendered?.image ?? large.values.first?.image ?? waiting?.image,
            textTone: rendered?.textTone ?? waiting?.tone ?? .ink,
            edges: rendered?.edges,
            tilt: CGSize(width: tilt.roll, height: -tilt.pitch)
        )
        .animation(Motion.quick, value: treatment)
        .task(id: "\(treatment.rawValue)-\(Int(width))-\(renderedRevision)") {
            await renderLarge(treatment, width: width)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 18) {
            if hasSymbol {
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(SymbolStyle.allCases, id: \.self) { option in
                            styleThumb(option)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.hidden)
            } else {
                Text(stamps.file(for: card.id)?.stamp?.source == .library
                     ? Copy.symbolIsRoasterLogo
                     : Copy.noSymbolOnThisPack)
                    .font(Typography.subtitle)
                    .foregroundStyle(Palette.inkMuted)
                    .padding(.horizontal, 24)
            }

            HStack(spacing: 18) {
                layoutChoice(Copy.layoutLabel, .label)
                layoutChoice(Copy.layoutFullBleed, .fullBleed)
                Spacer()
                redoButton
            }
            .padding(.horizontal, 24)

            if let redoOutcome {
                Text(redoOutcome)
                    .catalogueLabel()
                    .foregroundStyle(Palette.inkMuted)
                    .padding(.horizontal, 24)
                    .transition(.opacity)
            }
        }
        .padding(.bottom, 24)
    }

    private func styleThumb(_ option: SymbolStyle) -> some View {
        let shown = treatment(for: option)
        let selected = option == style
        return Button {
            withAnimation(Motion.quick) { style = option }
        } label: {
            VStack(spacing: 8) {
                Group {
                    if let image = thumbs[shown] {
                        Image(decorative: image, scale: displayScale)
                            .resizable()
                    } else {
                        Palette.hairline
                    }
                }
                .frame(width: Self.thumbWidth, height: Self.thumbWidth / CardTileLayout.aspectRatio)
                .clipShape(RoundedRectangle(cornerRadius: Self.thumbWidth * 0.05, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Self.thumbWidth * 0.05, style: .continuous)
                        .strokeBorder(selected ? Palette.ink : Color.clear, lineWidth: 1.5)
                        .padding(-3)
                }
                CatalogueMark(text: option.label, isSelected: selected)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func layoutChoice(_ title: String, _ choice: CardLayout) -> some View {
        Button {
            withAnimation(Motion.quick) { layout = choice }
        } label: {
            CatalogueMark(text: title, isSelected: layout == choice)
        }
        .buttonStyle(.plain)
    }

    private var redoButton: some View {
        Button {
            Task { await redo() }
        } label: {
            HStack(spacing: 6) {
                if isRedoing { ProgressView().controlSize(.mini) }
                Text(Copy.redoSymbol)
                    .catalogueLabel()
                    .foregroundStyle(Palette.ink)
            }
        }
        .buttonStyle(.plain)
        .disabled(isRedoing || !ImageStore.shared.exists(card.id, kind: .flat))
    }

    // MARK: - State

    private var file: StampFile? { stamps.file(for: card.id) }

    private var hasSymbol: Bool {
        guard let stamp = file?.stamp else { return false }
        return stamp.source != .library
    }

    private var treatment: SymbolTreatment { treatment(for: style) }

    private func treatment(for option: SymbolStyle) -> SymbolTreatment {
        guard var draft = file else { return .none }
        draft.style = option
        return draft.treatment(draw: CardArt.make(card, ink: file).symbolDraws[4])
    }

    // MARK: - Work

    private func renderAll() async {
        let revision = stamps.revision(for: card.id)
        large = [:]
        thumbs = [:]
        renderedRevision = revision
        let art = CardArt.make(card, ink: file)
        let mark = stamps.mark(for: card.id)
        let treatments = Set(SymbolStyle.allCases.map(treatment(for:)))
        let pixels = CGSize(
            width: Self.thumbWidth * displayScale,
            height: (Self.thumbWidth / CardTileLayout.aspectRatio * displayScale).rounded()
        )
        for each in treatments {
            let image = await Task.detached(priority: .userInitiated) {
                CardBackdrop.render(art, mark: each == .none ? nil : mark, treatment: each, size: pixels)?.image
            }.value
            guard !Task.isCancelled, revision == stamps.revision(for: card.id) else { return }
            thumbs[each] = image
        }
    }

    private func renderLarge(_ shown: SymbolTreatment, width: CGFloat) async {
        if large[shown] != nil { return }
        let art = CardArt.make(card, ink: file)
        let mark = stamps.mark(for: card.id)
        let scale = max(2, displayScale)
        let size = CGSize(width: width * scale, height: (width / CardTileLayout.aspectRatio * scale).rounded())
        let result = await Task.detached(priority: .userInitiated) {
            CardBackdrop.render(
                art,
                mark: shown == .none ? nil : mark,
                treatment: shown,
                size: size,
                separateEmbossEdges: shown == .emboss
            )
        }.value
        guard !Task.isCancelled, let result else { return }
        withAnimation(Motion.quick) { large[shown] = result }
    }

    private func redo() async {
        let before = file?.stamp
        isRedoing = true
        withAnimation(Motion.quick) { redoOutcome = nil }
        await InkStampPipeline.backfill(
            cardID: card.id,
            library: stamps,
            roasterName: card.roaster,
            force: true
        )
        isRedoing = false
        let after = file?.stamp
        let outcome: String
        if after == nil {
            outcome = Copy.noSymbolOnThisPack
        } else if after?.source == .library {
            outcome = Copy.symbolIsRoasterLogo
        } else if after?.rect == before?.rect {
            outcome = Copy.sameSymbolFound
        } else {
            outcome = Copy.newSymbolFound
        }
        withAnimation(Motion.quick) { redoOutcome = outcome }
    }

    private func save() {
        if style != stamps.style(for: card.id), file != nil {
            stamps.setStyle(style, for: card.id)
        }
        if layout != looks.layout(for: card.id) {
            looks.setLayout(layout, for: card.id)
        }
        if looks.resolved(card) == .scan {
            looks.setOverride(.kohi, for: card.id)
        }
        dismiss()
    }
}
