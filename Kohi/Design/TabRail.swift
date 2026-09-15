import SwiftUI

/// Catalogue labels over a hairline, not a tab bar.
///
/// A `TabView` would put a translucent slab at the bottom of the screen and
/// undo the one thing the grid is for: paper, edge to edge, with nothing
/// floating on it. This is the same grammar as every section heading in the
/// app — uppercase mono, tracked — with ink for the selected label and muted
/// ink for the others.
///
/// `.rail` rules one hairline under the whole row, for the level-1 catalogue.
/// `.active` rules it under the selected label only, for a level-2 rail nested
/// inside a screen that already has one.
struct TabRail<Tab: Identifiable & Equatable, Trailing: View>: View {
    enum Underline {
        case rail
        case active
    }

    let tabs: [Tab]
    @Binding var selection: Tab
    let underline: Underline
    let animation: Animation
    let title: (Tab) -> String
    let trailing: Trailing

    init(
        tabs: [Tab],
        selection: Binding<Tab>,
        underline: Underline = .rail,
        animation: Animation = Motion.snappy,
        title: @escaping (Tab) -> String,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.tabs = tabs
        _selection = selection
        self.underline = underline
        self.animation = animation
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                ForEach(tabs) { tab in
                    Button {
                        guard selection != tab else { return }
                        withAnimation(animation) { selection = tab }
                    } label: {
                        VStack(spacing: 6) {
                            Text(title(tab))
                                .font(Typography.label)
                                .tracking(Typography.labelTracking)
                                .textCase(.uppercase)
                                .foregroundStyle(selection == tab ? Palette.ink : Palette.inkMuted)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .allowsTightening(true)
                                .padding(.vertical, underline == .rail ? 10 : 0)

                            if underline == .active {
                                Rectangle()
                                    .fill(selection == tab ? Palette.ink : Color.clear)
                                    .frame(height: 1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
                trailing
            }

            if underline == .rail {
                Rectangle()
                    .fill(Palette.hairline)
                    .frame(height: 1)
            }
        }
    }
}

extension TabRail where Trailing == EmptyView {
    init(
        tabs: [Tab],
        selection: Binding<Tab>,
        underline: Underline = .rail,
        animation: Animation = Motion.snappy,
        title: @escaping (Tab) -> String
    ) {
        self.init(
            tabs: tabs,
            selection: selection,
            underline: underline,
            animation: animation,
            title: title
        ) {
            EmptyView()
        }
    }
}
