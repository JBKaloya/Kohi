import SwiftUI

/// One criterion as a pill. The pill is the result: the criterion's name
/// while nothing is picked, the values once they are. No count, no shadow,
/// no rule. Tapped, its values unfold from the pill's top-left corner.
struct FilterPicker: View {
    let facet: FilterFacet
    @Binding var active: ActiveFilters
    let isOpen: Bool
    let onToggle: () -> Void

    /// Past this many characters the pill ends on an ellipsis.
    static let titleLimit = 22

    /// Cut on a word, never inside a name.
    static func truncated(_ title: String, limit: Int = titleLimit) -> String {
        guard title.count > limit else { return title }
        var head = String(title.prefix(limit - 1))
        if let space = head.lastIndex(of: " ") { head = String(head[..<space]) }
        return head.trimmingCharacters(in: CharacterSet(charactersIn: " ,")) + "…"
    }

    var body: some View {
        Button(action: onToggle) {
            Text(Self.truncated(active.title(of: facet)))
        }
        .buttonStyle(FilterPillStyle(isOpen: isOpen))
        .accessibilityLabel(facet.label)
        .accessibilityValue(active.values(of: facet.id).isEmpty ? "" : active.title(of: facet))
        .overlay(alignment: .bottomLeading) {
            if isOpen {
                FilterOptionList(facet: facet, active: $active)
                    .fixedSize()
                    .alignmentGuide(.bottom) { $0[.top] - 6 }
                    .transition(.unfold)
            }
        }
        .zIndex(isOpen ? 1 : 0)
    }
}

private struct FilterPillStyle: ButtonStyle {
    let isOpen: Bool

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.label
                .font(Typography.tag)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(configuration.isPressed || isOpen ? Palette.ink : Palette.inkMuted)
                .rotationEffect(.degrees(isOpen ? 180 : 0))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(Palette.well))
        .contentShape(Capsule())
        .animation(Motion.quick, value: configuration.isPressed)
        .animation(Motion.unfold, value: isOpen)
    }
}

/// The values of a facet, on a card. A chosen value inverts in ink, the way
/// a chip does; there is no checkmark.
struct FilterOptionList: View {
    let facet: FilterFacet
    @Binding var active: ActiveFilters
    /// Off in snapshots, where an appearance never gets to run.
    var cascades = true

    static let corner: CGFloat = 14
    static let inset: CGFloat = 6
    /// Concentric with the card: its radius less the inset.
    static let rowCorner: CGFloat = corner - inset
    static let visibleRows = 7
    static let rowHeight: CGFloat = 34

    var body: some View {
        Group {
            if facet.options.count > Self.visibleRows {
                ScrollView { rows }
                    .frame(height: CGFloat(Self.visibleRows) * Self.rowHeight)
                    .scrollIndicators(.hidden)
            } else {
                rows
            }
        }
        .padding(Self.inset)
        .background(Palette.paper, in: RoundedRectangle(cornerRadius: Self.corner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Self.corner, style: .continuous).stroke(Palette.hairline, lineWidth: 1))
        .haptic(.step, trigger: active)
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(facet.options.enumerated()), id: \.element.id) { index, option in
                FilterOptionRow(
                    option: option,
                    isSelected: active.contains(option.id, in: facet.id),
                    index: index,
                    cascades: cascades
                ) {
                    withAnimation(Motion.quick) { active.toggle(option.id, in: facet) }
                }
            }
        }
    }
}

private struct FilterOptionRow: View {
    let option: FilterOption
    let isSelected: Bool
    let index: Int
    let cascades: Bool
    let action: () -> Void

    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                CatalogueMark(text: option.label, isSelected: isSelected)
                Spacer(minLength: 24)
            }
            .padding(.horizontal, 10)
            .frame(minWidth: 168, minHeight: FilterOptionList.rowHeight, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: FilterOptionList.rowCorner, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : -4)
        .onAppear {
            guard cascades, !reduceMotion, !shown else { return }
            withAnimation(Motion.unfold.delay(Double(index) * Motion.Unfold.rowStagger)) { shown = true }
        }
    }

    private var isVisible: Bool { shown || !cascades || reduceMotion }
}

private struct UnfoldEffect: ViewModifier {
    let folded: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(
                x: folded ? Motion.Unfold.scaleX : 1,
                y: folded ? Motion.Unfold.scaleY : 1,
                anchor: .topLeading
            )
            .offset(y: folded ? Motion.Unfold.lift : 0)
            .opacity(folded ? 0 : 1)
    }
}

extension AnyTransition {
    /// A list opening from the top-left corner of what opened it.
    static var unfold: AnyTransition {
        .modifier(active: UnfoldEffect(folded: true), identity: UnfoldEffect(folded: false))
    }
}

/// The tabs, a Filter button at their right, and the criteria under it. As
/// soon as one value is picked the tabs give way to what is filtering, as
/// chips to take out; the last one out brings the tabs back. The tab itself
/// is not touched, so it comes back as it was.
struct FilterBar<Tabs: View>: View {
    let facets: [FilterFacet]
    @Binding var active: ActiveFilters
    let tabs: Tabs

    @State private var showsFacets = false
    @State private var open: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(facets: [FilterFacet], active: Binding<ActiveFilters>, @ViewBuilder tabs: () -> Tabs) {
        self.facets = facets
        _active = active
        self.tabs = tabs()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                ZStack(alignment: .leading) {
                    if active.isEmpty {
                        tabs.transition(.opacity)
                    } else {
                        chips.transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(Motion.quick, value: active.isEmpty)

                Button {
                    withAnimation(Motion.quick) {
                        showsFacets.toggle()
                        open = nil
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(Copy.filter).catalogueLabel()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(showsFacets ? Palette.ink : Palette.inkMuted)
                            .rotationEffect(.degrees(showsFacets ? 180 : 0))
                    }
                }
                .buttonStyle(.plain)
                .touchTarget()
            }

            if showsFacets {
                FlowLayout {
                    ForEach(facets) { facet in
                        FilterPicker(facet: facet, active: $active, isOpen: open == facet.id) {
                            withAnimation(reduceMotion ? nil : Motion.unfold) {
                                open = open == facet.id ? nil : facet.id
                            }
                        }
                    }
                }
                .transition(.opacity)
            }
        }
        .background {
            if open != nil {
                // Any tap outside the open list closes it.
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: 4000, height: 4000)
                    .onTapGesture {
                        withAnimation(reduceMotion ? nil : Motion.unfold) { open = nil }
                    }
            }
        }
        .zIndex(1)
    }

    private var chips: some View {
        ChipRail {
            ForEach(active.chips(in: facets)) { chip in
                TagChip(text: chip.option.label, isSelected: true, showsRemove: true) {
                    withAnimation(Motion.quick) { active.remove(chip.option.id, from: chip.facetID) }
                }
                .accessibilityLabel("Remove \(chip.option.label)")
            }
        }
    }
}
