import SwiftUI
import Testing
import UIKit
@testable import Kohi

/// Writes one PNG per step of the main journeys, plus a flow diagram, into
/// `parcours-export/` at the repo root. Stays quiet unless `KOHI_EXPORT_PARCOURS=1`,
/// so a normal test run does not touch the archive or the folder.
@Suite(.serialized)
@MainActor
struct ParcoursExportTests {
    @Test func exportParcours() async throws {
        let folder = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "parcours-export", directoryHint: .isDirectory)
        // xcodebuild does not forward TEST_RUNNER_* into this hosted app, so a
        // `.run` marker in the export folder is the switch this run actually sees.
        let env = ProcessInfo.processInfo.environment
        let marker = folder.appending(path: ".run")
        let requested = env["KOHI_EXPORT_PARCOURS"] == "1"
            || env["TEST_RUNNER_KOHI_EXPORT_PARCOURS"] == "1"
            || FileManager.default.fileExists(atPath: marker.path)
        guard requested else { return }
        try? FileManager.default.removeItem(at: marker)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let token = UUID().uuidString
        var names = ExportNames(token: token)
        defer { names.remove() }

        let whitenKey = "scan.seenWhitenHint"
        let previousWhiten = UserDefaults.standard.object(forKey: whitenKey)
        defer {
            if let previousWhiten {
                UserDefaults.standard.set(previousWhiten, forKey: whitenKey)
            } else {
                UserDefaults.standard.removeObject(forKey: whitenKey)
            }
        }

        let defaults = UserDefaults(suiteName: "kohi-parcours-\(token)")!
        let setup = filledKit(filename: names.setupFilled)
        let emptySetup = SetupStore(files: JSONDocumentStore(filename: names.setupEmpty))
        let store = CardStore(files: CardFileStore(url: names.cardsURL))
        let recipes = RecipeStore(files: JSONFileStore(filename: names.recipes))
        let world = AppEnvironment(
            store: store,
            roasters: RoasterStore(
                files: JSONFileStore(filename: names.roasters),
                seedStamp: JSONDocumentStore(filename: names.roasterStamp)
            ),
            places: PlaceIndex(notes: JSONDocumentStore(filename: names.places)),
            setup: setup,
            recipes: recipes,
            tastings: TastingStore(
                files: JSONFileStore(filename: "tastings-parcours-\(token).json"),
                ledgerFile: JSONDocumentStore(filename: "tastings-ledger-parcours-\(token).json")
            ),
            account: AccountStore(),
            setupFlow: SetupFlowController(),
            sync: SyncCoordinator(outbox: SyncOutbox()),
            flags: AIFlags(defaults: defaults),
            lotFlags: LotFlags(defaults: defaults),
            aiEvents: AIEventLog(),
            feedback: AIFeedbackStore(files: JSONFileStore(filename: names.feedback)),
            cardLooks: CardLookStore(defaults: defaults),
            stamps: StampLibrary(),
            stampRefresh: StampRefresh()
        )
        let emptyWorld = world.replacing(setup: emptySetup)

        var seeded = SampleArchive.seed()
        try #require(!seeded.isEmpty, "Sample cards did not load from the app bundle.")
        let older = Brew(
            date: Date(timeIntervalSinceNow: -86_400),
            method: .v60,
            dose: 15,
            water: 250,
            seconds: 195,
            grind: GrindSetting(raw: "20 clicks"),
            temperature: 96,
            rating: 3,
            notes: "Thin."
        )
        let newer = Brew(
            method: .v60,
            dose: 15,
            water: 250,
            seconds: 180,
            grind: GrindSetting(raw: "22 clicks"),
            temperature: 94,
            rating: 4,
            notes: "Blackcurrant, a bit sharp."
        )
        seeded[0].brews = [newer, older]
        seeded[0].tastings = [
            Tasting(context: .home(brewID: newer.id), rating: 4, note: "At the table.")
        ]
        seeded[0].roastLevel = .light
        let featured = seeded[0]
        for card in seeded {
            store.add(card)
        }
        names.seededIDs = seeded.map(\.id)

        recipes.add(Recipe(
            name: "V60 · Kenya",
            method: .v60,
            dose: 15,
            water: 250,
            temperature: 94,
            seconds: 180,
            grindLabel: "22 clicks",
            source: .mine,
            cardID: featured.id
        ))

        let bareStore = CardStore(files: CardFileStore(url: names.bareCardsURL))
        for var card in seeded {
            card.brews = []
            card.tastings = []
            bareStore.add(card)
        }
        var bareWorld = world
        bareWorld.store = bareStore

        let reference = try #require(
            ReferenceBase.recipe(referenceID: "a1-v60-ultimate"),
            "Missing the bundled V60 recipe."
        )
        let capture = try #require(
            SampleArchive.sampleCapture() ?? Self.flatCapture(),
            "No sample card for the review screen."
        )

        let pages: [(String, CGFloat, Duration, Bool, AnyView)] = [
            ("01-archive-grille", 852, .seconds(2.5), false, AnyView(ArchiveGrid().appEnvironment(world))),
            ("01-archive-fiche", 3600, .seconds(2), true, AnyView(CardDetailView(card: featured).appEnvironment(world))),
            ("02-scan-revue", 852, .seconds(2.5), false, AnyView(
                ScanReviewScreen(capture: capture, onUse: { _ in }, onRetake: {})
                    .environment(\.kohiHapticsEnabled, false)
            )),
            ("02-scan-fiche", 3900, .seconds(1), true, AnyView(
                CardEditSheet(card: Self.draftCard(), isNew: true, onSave: { _ in })
                    .appEnvironment(world)
            )),
            ("03-setup-entree", 852, .milliseconds(900), false, AnyView(
                SetupFlowSheet(exportStage: .entry).appEnvironment(emptyWorld)
            )),
            ("03-setup-methode", 852, .milliseconds(900), false, AnyView(
                SetupFlowSheet(exportStage: .brew).appEnvironment(emptyWorld)
            )),
            ("03-setup-broyeur", 852, .milliseconds(900), false, AnyView(
                SetupFlowSheet(exportStage: .grind).appEnvironment(emptyWorld)
            )),
            ("03-setup-eau", 852, .milliseconds(900), false, AnyView(
                SetupFlowSheet(exportStage: .water).appEnvironment(emptyWorld)
            )),
            ("03-setup-profil", 2800, .milliseconds(900), true, AnyView(
                ProfileSheet().appEnvironment(world)
            )),
            ("04-brew-scope", 852, .milliseconds(800), false, AnyView(
                BrewStepPage(session: BrewSession(card: featured, recipe: reference, start: .scope, setup: setup))
                    .appEnvironment(world)
            )),
            ("04-brew-kit", 852, .milliseconds(800), false, AnyView(
                BrewStepPage(session: BrewSession(card: featured, recipe: reference, start: .kit, setup: setup))
                    .appEnvironment(world)
            )),
            ("04-brew-dial", 852, .milliseconds(800), false, AnyView(
                BrewStepPage(session: BrewSession(card: featured, recipe: reference, start: .dial, setup: setup))
                    .appEnvironment(world)
            )),
            ("04-brew-pour", 852, .milliseconds(800), false, AnyView(
                Self.pour(featured, recipe: reference, setup: setup).appEnvironment(world)
            )),
            ("04-brew-after", 852, .milliseconds(800), false, AnyView(
                Self.after(featured, brew: newer, recipe: reference, setup: setup).appEnvironment(world)
            )),
            ("05-recettes-suggested", 852, .milliseconds(900), false, AnyView(RecipePage(tab: .all).appEnvironment(bareWorld))),
            ("05-recettes-pros", 852, .milliseconds(900), false, AnyView(RecipePage(tab: .reference).appEnvironment(world))),
            ("05-recettes-mine", 852, .milliseconds(900), false, AnyView(RecipePage(tab: .mine).appEnvironment(world))),
            ("05-recette-detail", 852, .milliseconds(800), false, AnyView(
                RecipeDetailSheet(recipe: reference, provenance: .reference(reference.attribution), card: featured)
                    .appEnvironment(world)
            )),
            ("06-compare", 1800, .milliseconds(800), true, AnyView(
                BrewCompareSheet(
                    card: featured,
                    reference: newer,
                    equipment: setup.equipment
                )
                .appEnvironment(world)
            )),
        ]

        for page in pages {
            let image = try await ParcoursPNG.render(
                page.4,
                height: page.1,
                settle: page.2,
                cropPaper: page.3,
                name: page.0
            )
            try ParcoursPNG.write(image, named: page.0, to: folder)
        }

        let schema = try await ParcoursPNG.render(
            AnyView(ParcoursSchema()),
            width: 1180,
            height: 700,
            settle: .milliseconds(400),
            cropPaper: true,
            name: "00-schema"
        )
        try ParcoursPNG.write(schema, named: "00-schema", to: folder)
        try Self.readme.write(
            to: folder.appending(path: "LISEZMOI.md"),
            atomically: true,
            encoding: .utf8
        )
    }

    private static func pour(_ card: CoffeeCard, recipe: Recipe, setup: SetupStore) -> some View {
        let session = BrewSession(card: card, recipe: recipe, start: .pour, setup: setup)
        return GuidedBrewView(
            card: session.card,
            recipe: session.timerRecipe(in: setup),
            brew: session.brew,
            voiceNote: session.voiceNote,
            equipment: setup.equipment,
            onFinish: { _ in },
            onCancel: {},
            startsRunning: false,
            journeyStep: session.progressIndex,
            journeyTotal: session.progressTotal
        )
    }

    private static func after(
        _ card: CoffeeCard,
        brew: Brew,
        recipe: Recipe,
        setup: SetupStore
    ) -> some View {
        let session = BrewSession(
            card: card,
            recipe: recipe,
            existing: brew,
            start: .after,
            setup: setup
        )
        return BrewFlowHost(session: session, onDismiss: {})
    }

    /// A still of one bundled card, used when the warped sample cannot be built.
    private static func flatCapture() -> CapturedCard? {
        guard
            let url = Bundle.main.url(forResource: "ethiopia-chelbesa", withExtension: "png"),
            let image = ImageCodec.decode(url)
        else { return nil }
        return CapturedCard(image: image, quad: nil)
    }

    private static func draftCard() -> CoffeeCard {
        CoffeeCard(
            name: "Chelbesa",
            roaster: "Gardelli",
            country: "Ethiopia",
            region: "Gedeb, Gedeo",
            producer: "Chelbesa Washing Station",
            altitude: "2050m",
            variety: "Heirloom Landrace",
            process: "Natural",
            tastingNotes: ["Blueberry", "Jasmine", "Cane Sugar"],
            brewMethod: .filter
        )
    }

    private static let readme = """
    # Parcours Kohi

    Une image par étape, à déposer dans Freeform. Le schéma est `00-schema.png`.

    La visée caméra n'est pas là : au simulateur ce n'est pas l'écran réel. L'IA et le compte non plus. Brasser depuis une recette reprend Scope, sans image en plus.

    ## Archive
    - `01-archive-grille.png` — grille des six cartes d'exemple
    - `01-archive-fiche.png` — fiche, en entier

    ## Scan
    - `02-scan-revue.png` — revue, coins et Whiten
    - `02-scan-fiche.png` — New card, en entier

    ## Matériel
    - `03-setup-entree.png` — Bring what you have
    - `03-setup-methode.png` — How do you brew?
    - `03-setup-broyeur.png` — What do you grind with?
    - `03-setup-eau.png` — What water?
    - `03-setup-profil.png` — Profil, le kit déclaré

    ## Brew
    - `04-brew-scope.png` — Scope
    - `04-brew-kit.png` — Kit
    - `04-brew-dial.png` — How much?
    - `04-brew-pour.png` — Pour, arrêté sur le bloc en cours
    - `04-brew-after.png` — After
    - `06-compare.png` — comparaison de deux tasses

    ## Recettes
    - `05-recettes-suggested.png` — All, no brew yet, one row per coffee
    - `05-recettes-pros.png` — From the pros
    - `05-recettes-mine.png` — My recipes
    - `05-recette-detail.png` — fiche d'une recette de référence
    """
}

private func filledKit(filename: String) -> SetupStore {
    let setup = SetupStore(files: JSONDocumentStore(filename: filename))
    let paper = BrewFilter(brand: "Hario", shape: "01")
    let brewer = Equipment(
        kind: .brewer,
        brand: "Hario",
        model: "V60",
        filters: [paper],
        defaultFilterId: paper.id
    )
    let kettle = Equipment(
        kind: .kettle,
        brand: "Fellow",
        model: "Stagg EKG",
        isGooseneck: true
    )
    let grinder = Equipment(
        kind: .grinder,
        brand: "1Zpresso",
        model: "J-Ultra",
        adjustment: .clicks,
        ranges: [GrindRange(method: .v60, low: 18, high: 36)]
    )
    let water = WaterProfile(name: "Tap", source: .tap, isDefault: true)
    setup.add(brewer)
    setup.setDefault(brewer, for: .v60, on: true)
    setup.add(kettle)
    setup.setDefault(kettle, for: .v60, on: true)
    setup.add(grinder)
    setup.setDefault(grinder, for: .v60, on: true)
    setup.add(water)
    setup.makeDefault(water)
    return setup
}

private struct BrewStepPage: View {
    let session: BrewSession

    var body: some View {
        BrewFlowHost(session: session, onDismiss: {})
    }
}

private struct ArchiveGrid: View {
    @State private var openCard: CoffeeCard?

    var body: some View {
        GridScreen(onScan: { _ in }, openCard: $openCard, cupScan: .constant(nil))
    }
}

private struct RecipePage: View {
    let tab: RecipeTab

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                CatalogueTabs(selection: .constant(.recipes))
                    .padding(.horizontal, 26)
                RecipesScreen(initialTab: tab)
            }
            .background(Palette.paper.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Kohi")
                        .font(Typography.brand)
                        .foregroundStyle(Palette.ink)
                }
            }
        }
    }
}

private struct ParcoursSchema: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Kohi — parcours")
                .font(Typography.brand)
                .foregroundStyle(Palette.ink)
            Text("Une image par étape. La visée caméra, l'IA et le compte ne sont pas dans ce paquet.")
                .font(Typography.subtitle)
                .foregroundStyle(Palette.inkMuted)
            lane("Archive", steps: [
                ("Grille", "01-archive-grille"),
                ("Fiche", "01-archive-fiche"),
            ])
            lane("Scan", steps: [
                ("Revue", "02-scan-revue"),
                ("New card", "02-scan-fiche"),
            ])
            lane("Matériel", steps: [
                ("Entrée", "03-setup-entree"),
                ("Méthode", "03-setup-methode"),
                ("Broyeur", "03-setup-broyeur"),
                ("Eau", "03-setup-eau"),
                ("Profil", "03-setup-profil"),
            ])
            Text("New card mène au setup. La fiche et la fiche recette mènent à Scope.")
                .font(Typography.tag)
                .foregroundStyle(Palette.inkMuted)
            lane("Brew", steps: [
                ("Scope", "04-brew-scope"),
                ("Kit", "04-brew-kit"),
                ("Dial", "04-brew-dial"),
                ("Pour", "04-brew-pour"),
                ("After", "04-brew-after"),
                ("Comparaison", "06-compare"),
            ])
            lane("Recettes", steps: [
                ("All", "05-recettes-suggested"),
                ("From the pros", "05-recettes-pros"),
                ("My recipes", "05-recettes-mine"),
                ("Fiche recette", "05-recette-detail"),
            ])
            Text("Brasser depuis une recette reprend Scope.")
                .font(Typography.tag)
                .foregroundStyle(Palette.inkMuted)
        }
        .padding(32)
        .frame(width: 1180, alignment: .topLeading)
        .background(Palette.paper)
    }

    private func lane(_ title: String, steps: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(Typography.label)
                .tracking(Typography.labelTracking)
                .foregroundStyle(Palette.inkMuted)
            HStack(spacing: 8) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    if index > 0 {
                        Text("→")
                            .font(Typography.subtitle)
                            .foregroundStyle(Palette.inkMuted)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(step.0)
                            .font(Typography.value)
                            .foregroundStyle(Palette.ink)
                        Text(step.1)
                            .font(Typography.tag)
                            .foregroundStyle(Palette.inkMuted)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .overlay(Rectangle().stroke(Palette.hairline, lineWidth: 1))
                }
            }
        }
    }
}

private extension AppEnvironment {
    func replacing(setup: SetupStore) -> AppEnvironment {
        var copy = self
        copy.setup = setup
        return copy
    }
}

/// Temp files this export creates, so a run does not leave them in Application Support.
private struct ExportNames {
    let token: String
    var seededIDs: [UUID] = []

    var setupEmpty: String { "parcours-setup-empty-\(token).json" }
    var setupFilled: String { "parcours-setup-filled-\(token).json" }
    var recipes: String { "parcours-recipes-\(token).json" }
    var roasters: String { "parcours-roasters-\(token).json" }
    var roasterStamp: String { "parcours-roaster-stamp-\(token).json" }
    var places: String { "parcours-places-\(token).json" }
    var feedback: String { "parcours-feedback-\(token).json" }
    var cardsURL: URL {
        FileManager.default.temporaryDirectory.appending(path: "parcours-cards-\(token).json")
    }
    var bareCardsURL: URL {
        FileManager.default.temporaryDirectory.appending(path: "parcours-cards-bare-\(token).json")
    }

    func remove() {
        for id in seededIDs {
            ImageStore.shared.removeAll(for: id)
        }
        let support = URL.applicationSupportDirectory
        for name in [setupEmpty, setupFilled, recipes, roasters, roasterStamp, places, feedback] {
            try? FileManager.default.removeItem(at: support.appending(path: name))
        }
        try? FileManager.default.removeItem(at: cardsURL)
        try? FileManager.default.removeItem(at: bareCardsURL)
        // BrewJourneySupport.setup() writes its own setup file.
    }
}

private enum ExportError: Error, CustomStringConvertible {
    case noScroll(String)

    var description: String {
        switch self {
        case .noScroll(let name): "\(name) has no scroll view, so the long sheet cannot be paged."
        }
    }
}

@MainActor
private enum ParcoursPNG {
    final class FrameWindow: UIWindow {
        override var safeAreaInsets: UIEdgeInsets { .zero }
    }

    static func render<V: View>(
        _ view: V,
        width: CGFloat = 393,
        height: CGFloat,
        settle: Duration,
        cropPaper: Bool,
        name: String
    ) async throws -> UIImage {
        // drawHierarchy returns an empty bitmap once a view is taller than
        // about 2000 pt. Long sheets are hosted at a page and advanced.
        let image: UIImage
        if height <= 2000 {
            image = try await capture(view, width: width, height: height, settle: settle)
        } else {
            image = try await capturePages(view, width: width, pageHeight: 1400, settle: settle, name: name)
        }
        guard cropPaper else { return image }
        let (cropped, clipped) = crop(image)
        try #require(!clipped, "\(name) is full: raise its height so the step is not cut off.")
        return cropped
    }

    private static func capture<V: View>(
        _ view: V,
        width: CGFloat,
        height: CGFloat,
        settle: Duration
    ) async throws -> UIImage {
        let root = view
            .frame(width: width, height: height, alignment: .top)
            .background(Palette.paper)
            .environment(\.kohiHapticsEnabled, false)
        let controller = UIHostingController(rootView: root)
        let paper = UIColor(red: 0.980, green: 0.973, blue: 0.957, alpha: 1)
        controller.view.backgroundColor = paper
        let frame = CGRect(x: 0, y: 0, width: width, height: height)
        let window = FrameWindow(frame: frame)
        window.overrideUserInterfaceStyle = .light
        window.backgroundColor = paper
        window.rootViewController = controller
        attach(window)
        window.frame = frame
        controller.view.frame = frame
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        try await Task.sleep(for: settle)
        controller.view.layoutIfNeeded()
        let image = bitmap(of: window, size: frame.size)
        window.isHidden = true
        window.windowScene = nil
        window.rootViewController = nil
        return image
    }

    /// Hosts a long sheet at one page and stitches each scroll position.
    private static func capturePages<V: View>(
        _ view: V,
        width: CGFloat,
        pageHeight: CGFloat,
        settle: Duration,
        name: String
    ) async throws -> UIImage {
        let root = view
            .frame(width: width, height: pageHeight, alignment: .top)
            .background(Palette.paper)
            .environment(\.kohiHapticsEnabled, false)
        let controller = UIHostingController(rootView: root)
        let paper = UIColor(red: 0.980, green: 0.973, blue: 0.957, alpha: 1)
        controller.view.backgroundColor = paper
        let frame = CGRect(x: 0, y: 0, width: width, height: pageHeight)
        let window = FrameWindow(frame: frame)
        window.overrideUserInterfaceStyle = .light
        window.backgroundColor = paper
        window.rootViewController = controller
        attach(window)
        window.frame = frame
        controller.view.frame = frame
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        try await Task.sleep(for: settle)
        controller.view.layoutIfNeeded()

        let scrolls = scrollViews(in: controller.view)
            .filter { $0.contentSize.height > $0.bounds.height + 40 }
        guard let scroll = scrolls.max(by: { $0.contentSize.height < $1.contentSize.height }) else {
            window.isHidden = true
            window.windowScene = nil
            window.rootViewController = nil
            throw ExportError.noScroll(name)
        }
        scroll.showsVerticalScrollIndicator = false

        var pages: [UIImage] = []
        var offset: CGFloat = 0
        let content = scroll.contentSize.height
        while offset < content - 1 {
            scroll.setContentOffset(CGPoint(x: 0, y: offset), animated: false)
            scroll.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(150))
            pages.append(bitmap(of: window, size: frame.size))
            offset += pageHeight
        }
        window.isHidden = true
        window.windowScene = nil
        window.rootViewController = nil
        try #require(!pages.isEmpty, "\(name) produced no pages.")
        return pages.count == 1 ? pages[0] : stitch(pages)
    }

    /// Without a scene, drawHierarchy returns an empty bitmap for some sheets.
    private static func attach(_ window: UIWindow) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        window.windowScene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        window.makeKeyAndVisible()
    }

    private static func bitmap(of window: UIWindow, size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            window.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
        }
    }

    private static func scrollViews(in view: UIView) -> [UIScrollView] {
        var found: [UIScrollView] = []
        if let scroll = view as? UIScrollView { found.append(scroll) }
        for child in view.subviews {
            found.append(contentsOf: scrollViews(in: child))
        }
        return found
    }

    private static func stitch(_ pages: [UIImage]) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = pages[0].scale
        format.opaque = true
        let size = CGSize(
            width: pages[0].size.width,
            height: pages.reduce(0) { $0 + $1.size.height }
        )
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            var y: CGFloat = 0
            for page in pages {
                page.draw(in: CGRect(x: 0, y: y, width: page.size.width, height: page.size.height))
                y += page.size.height
            }
        }
    }

    static func write(_ image: UIImage, named name: String, to folder: URL) throws {
        let url = folder.appending(path: "\(name).png")
        guard let data = image.pngData() else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url, options: .atomic)
    }

    /// Drops the empty band under a tall sheet. The band is whatever flat colour
    /// fills the bottom, not a hardcoded paper value. `clipped` is true when
    /// the last row still varies, so the content runs off the frame.
    private static func crop(_ image: UIImage, paddingPoints: CGFloat = 56) -> (UIImage, Bool) {
        guard let cg = image.cgImage else { return (image, false) }
        let width = cg.width
        let height = cg.height
        let rowBytes = width * 4
        var buffer = [UInt8](repeating: 0, count: rowBytes * height)
        let drew = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: rowBytes,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return false }
            ctx.translateBy(x: 0, y: CGFloat(height))
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drew else { return (image, false) }

        func sample(_ x: Int, _ y: Int) -> (Int, Int, Int) {
            let index = y * rowBytes + x * 4
            return (Int(buffer[index]), Int(buffer[index + 1]), Int(buffer[index + 2]))
        }

        func close(_ a: (Int, Int, Int), _ b: (Int, Int, Int)) -> Bool {
            abs(a.0 - b.0) <= 8 && abs(a.1 - b.1) <= 8 && abs(a.2 - b.2) <= 8
        }

        func rowIsFlat(_ y: Int, like reference: (Int, Int, Int)) -> Bool {
            var x = 0
            while x < width {
                if !close(sample(x, y), reference) { return false }
                x += 8
            }
            return true
        }

        let background = sample(width / 2, height - 1)
        guard rowIsFlat(height - 1, like: background) else { return (image, true) }

        var y = height - 1
        while y >= 0 && rowIsFlat(y, like: background) {
            y -= 1
        }
        let padding = Int(paddingPoints * image.scale)
        let target = min(height, max(y + padding, 1))
        guard target < height - 2, let cropped = cg.cropping(to: CGRect(x: 0, y: 0, width: width, height: target)) else {
            return (image, false)
        }
        return (UIImage(cgImage: cropped, scale: image.scale, orientation: .up), false)
    }
}
