import SwiftUI

/// The one main screen. A vertical grid of cards on paper, a pinch to change how
/// many fit across, and a single button to add another.
struct GridScreen: View {
    let onScan: () -> Void

    @Environment(CardStore.self) private var store
    @Environment(\.displayScale) private var displayScale

    @State private var density: GridDensity = .three
    @State private var densityChanges = 0
    @State private var gridWidth: CGFloat = 0
    /// Live magnification during a pinch. The grid is scaled rather than relaid
    /// out on every frame; it looks identical and costs nothing.
    @State private var pinch: CGFloat = 1
    @State private var selection: CoffeeCard?
    @Namespace private var namespace

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.paper.ignoresSafeArea()

                if store.cards.isEmpty {
                    EmptyStateView()
                } else {
                    grid
                }

                VStack {
                    Spacer()
                    ScanButton(action: onScan)
                        .padding(.bottom, 26)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .haptic(.densityChange, trigger: densityChanges)
            .navigationDestination(item: $selection) { card in
                CardDetailView(card: card)
                    .navigationTransition(.zoom(sourceID: card.id, in: namespace))
            }
            .task { await openFirstCardIfRequested() }
        }
        .tint(Palette.ink)
    }

    private var grid: some View {
        GeometryReader { proxy in
            let metrics = Metrics(width: proxy.size.width, density: density)

            ScrollViewReader { scroller in
                ScrollView {
                    LazyVGrid(columns: metrics.columns, spacing: density.spacing) {
                        ForEach(store.cards) { card in
                            CardTile(
                                card: card,
                                width: metrics.tileWidth,
                                namespace: namespace
                            ) {
                                selection = card
                            }
                            .id(card.id)
                        }
                    }
                    .padding(.horizontal, density.horizontalPadding)
                    // Deep top and bottom insets are most of what makes the
                    // scroll feel like it has no ends.
                    .padding(.top, 92)
                    .padding(.bottom, 190)
                }
                .scrollIndicators(.hidden)
                .scaleEffect(pinchScale, anchor: .center)
                .simultaneousGesture(pinchGesture)
                .onChange(of: store.landingCardID) { _, landing in
                    // A new card goes to the top of the archive, so bring the
                    // top of the archive into view to watch it arrive.
                    guard let landing else { return }
                    withAnimation(Motion.gentle) {
                        scroller.scrollTo(landing, anchor: .top)
                    }
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gridWidth = $0 }
    }

    /// Damped so a wild pinch does not throw the grid off screen before it snaps.
    private var pinchScale: CGFloat {
        let damped = 1 + (pinch - 1) * Motion.Grid.pinchDamping
        return min(max(damped, Motion.Grid.pinchClamp.lowerBound), Motion.Grid.pinchClamp.upperBound)
    }

    private var pinchGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: Motion.Grid.minimumScaleDelta)
            .onChanged { value in
                pinch = value.magnification
            }
            .onEnded { value in
                let target = density.stepped(by: value.magnification)
                if target != density {
                    densityChanges += 1
                    prewarm(for: target)
                }
                withAnimation(Motion.snappy) {
                    pinch = 1
                    density = target
                }
            }
    }

    /// One and two columns read from the 1024 bucket, three and four from 512,
    /// so only a pinch across that boundary needs anything decoded. When it
    /// happens, get ahead of it for the cards most likely to be on screen.
    private func prewarm(for target: GridDensity) {
        let current = ThumbnailCache.bucket(forWidth: tileWidth(for: density), scale: displayScale)
        let next = ThumbnailCache.bucket(forWidth: tileWidth(for: target), scale: displayScale)
        guard current != next else { return }
        for card in store.cards.prefix(Motion.Grid.prewarmCount) {
            ThumbnailCache.shared.warm(card, buckets: [next])
        }
    }

    private func tileWidth(for density: GridDensity) -> CGFloat {
        Metrics(width: gridWidth, density: density).tileWidth
    }

    /// Development shortcut: `SIMCTL_CHILD_KOHI_OPEN_FIRST=1` opens the newest
    /// card on launch so the detail view can be iterated on without tapping.
    private func openFirstCardIfRequested() async {
        #if DEBUG
        guard DebugHooks.opensFirstCard else { return }
        try? await Task.sleep(for: .seconds(1))
        selection = store.cards.first
        #endif
    }

    private struct Metrics {
        let columns: [GridItem]
        let tileWidth: CGFloat

        init(width: CGFloat, density: GridDensity) {
            let spacing = density.spacing
            let available = width
                - density.horizontalPadding * 2
                - spacing * CGFloat(density.columns - 1)
            tileWidth = max(1, available / CGFloat(density.columns))
            columns = Array(
                repeating: GridItem(.flexible(), spacing: spacing, alignment: .top),
                count: density.columns
            )
        }
    }
}
