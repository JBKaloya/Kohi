import SwiftUI

/// One criterion as a pill. The pill is the result: the criterion's name
/// while nothing is picked, the values once they are. No count, no shadow,
/// no rule. Tapped, its values hang below it and unfold from that corner.
struct FilterPicker: View {
    let facet: FilterFacet
    @Binding var active: ActiveFilters
    let isOpen: Bool
    /// Where the pill landed, in the filter bar's coordinate space. The open
    /// list is drawn by the bar, not by the pill: an overlay on the pill
    /// aligns to the pill's bottom and so grows up over the title.
    var onFrame: (CGRect) -> Void = { _ in }
    let onToggle: () -> Void

    /// How far under the pill the list starts.
    static let menuGap: CGFloat = 6

    /// The list leads with the pill, and never past the bar's right edge.
    static func menuLead(pillMinX: CGFloat, barWidth: CGFloat, menuWidth: CGFloat) -> CGFloat {
        let natural = max(pillMinX, 0)
        guard menuWidth > 1, barWidth > 1 else { return natural }
        return min(natural, max(0, barWidth - menuWidth))
    }

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
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(FilterBarSpace.name)) }, action: onFrame)
        .zIndex(isOpen ? 1 : 0)
    }
}

private enum FilterBarSpace {
    static let name = "filter-bar"
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
    /// A list opening from its top-left corner, the one against the pill.
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
    /// The pill the list last hung from. Kept while the list folds shut,
    /// so the exit still has a corner to fold into.
    @State private var anchor: String?
    @State private var frames: [String: CGRect] = [:]
    @State private var barWidth: CGFloat = 0
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
                        FilterPicker(
                            facet: facet,
                            active: $active,
                            isOpen: open == facet.id,
                            onFrame: { frames[facet.id] = $0 }
                        ) {
                            withAnimation(reduceMotion ? nil : Motion.unfold) {
                                if open == facet.id {
                                    open = nil
                                } else {
                                    anchor = facet.id
                                    open = facet.id
                                }
                            }
                        }
                    }
                }
                .transition(.opacity)
            }
        }
        .coordinateSpace(name: FilterBarSpace.name)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { barWidth = $0 }
        .overlay(alignment: .topLeading) { hangingList }
        .background {
            if open != nil {
                // Any tap outside the open list closes it. The catcher lives
                // on the bar, above the scrolling list, so a tap on a row
                // underneath still dismisses.
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

    /// The open list, laid out under the pill that opened it. Spacers take
    /// the gap and do not take taps, so the pill underneath still toggles.
    @ViewBuilder
    private var hangingList: some View {
        if let id = anchor, let pill = frames[id], pill.width > 1,
           let facet = facets.first(where: { $0.id == id }) {
            HangingFilterList(
                facet: facet,
                active: $active,
                pill: pill,
                barWidth: barWidth,
                shown: open == id
            )
            .id(id)
            .transition(.identity)
        }
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

/// The open values, hung under the pill. The clear spacers are the gap:
/// they keep the list's own top-left on the pill's bottom-left, which is
/// the corner `unfold` scales from, and they pass taps through.
private struct HangingFilterList: View {
    let facet: FilterFacet
    @Binding var active: ActiveFilters
    let pill: CGRect
    let barWidth: CGFloat
    let shown: Bool

    @State private var menuWidth: CGFloat = 0

    var body: some View {
        let lead = FilterPicker.menuLead(pillMinX: pill.minX, barWidth: barWidth, menuWidth: menuWidth)
        HStack(alignment: .top, spacing: 0) {
            Color.clear
                .frame(width: lead, height: 1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: FilterPicker.menuGap) {
                Color.clear
                    .frame(width: 1, height: max(pill.maxY, 0))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                if shown {
                    FilterOptionList(facet: facet, active: $active)
                        .fixedSize()
                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { menuWidth = $0 }
                        .transition(.unfold)
                }
            }
        }
    }
}
