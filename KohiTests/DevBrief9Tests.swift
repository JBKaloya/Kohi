import CoreGraphics
import Foundation
import ImageIO
import Testing
import UIKit
@testable import Kohi

/// Dev brief 9: the Kohi card is a small landscape, and it is the standard.
@Suite(.serialized)
@MainActor
struct DevBrief9Tests {
    // MARK: - Parity with the card lab

    private struct Vectors: Decodable {
        struct Vector: Decodable {
            var id: String
            var name: String
            var seedHex: String
            var firstRandoms: [Double]
            var process: String
            var altitudeShare: Double
            var side: String
            var stickerRotationDeg: Double
            var titleInk: String
            var fieldAtCenter: String
            var fieldAtTop: String
        }
        var vectors: [Vector]
    }

    /// The first five coffees of `docs/card-lab/src/lab/data.js`, as the prototype sees them.
    private struct LabCard {
        var id: String
        var country: String
        var altitude: String
        var process: String
        var roast: RoastLevel?
        var notes: [String]
        var inkHue: Double?
    }

    private static let labCards: [LabCard] = [
        LabCard(id: "0b6e2c1a-7d4f-4e8a-9a51-3c2f8e6b1d01", country: "Ethiopia", altitude: "2048", process: "Washed", roast: .light, notes: ["Floral", "Citrus", "Stonefruits"], inkHue: 0.64),
        LabCard(id: "5c1d9f02-3b8e-41f7-8d2c-6a4e0f9b7c12", country: "Kenya", altitude: "1800", process: "Washed", roast: .light, notes: ["Floral", "Red Currant", "Vanilla"], inkHue: nil),
        LabCard(id: "9a7e3c44-1f2b-4d6e-b0a8-2e5c7d9f1a23", country: "Ethiopia", altitude: "2050", process: "Natural", roast: .light, notes: ["Blueberry", "Jasmine", "Cane Sugar"], inkHue: nil),
        LabCard(id: "e2f4a6b8-c0d2-4e6f-8a0b-1c3d5e7f9a34", country: "Colombia", altitude: "1930", process: "Double Anaerobic", roast: .light, notes: ["Lychee", "Rose", "Passionfruit"], inkHue: nil),
        LabCard(id: "3d5f7a9c-b1e3-4f5a-9c7e-0b2d4f6a8c45", country: "Peru", altitude: "1825", process: "Lavado", roast: nil, notes: ["Orange", "Crisp Apple", "Dark Chocolate"], inkHue: 0.60),
    ]

    private static func art(_ lab: LabCard) -> CardArt {
        CardArt.make(
            id: UUID(uuidString: lab.id)!, country: lab.country, altitude: lab.altitude, process: lab.process,
            roast: lab.roast, decaf: false, notes: lab.notes, inkHue: lab.inkHue
        )
    }

    private static func vectors() throws -> [Vectors.Vector] {
        let url = Self.repoRoot.appending(path: "docs/card-lab/card-art-vectors.json")
        return try JSONDecoder().decode(Vectors.self, from: Data(contentsOf: url)).vectors
    }

    @Test func seedAndFirstDrawsMatchThePrototype() throws {
        let vectors = try Self.vectors()
        #expect(vectors.count == 5)
        for vector in vectors {
            let id = UUID(uuidString: vector.id)!
            let seed = CardSeed.seed(for: id)
            #expect(String(format: "%08x", seed) == vector.seedHex, "\(vector.name)")
            var rnd = Mulberry32(seed: seed)
            for expected in vector.firstRandoms {
                let draw = rnd.unit()
                #expect(abs(draw - expected) < 5e-7, "\(vector.name): \(draw) vs \(expected)")
            }
        }
    }

    @Test func fieldMatchesThePrototypeWithinTwoLevels() throws {
        let vectors = try Self.vectors()
        for (vector, lab) in zip(vectors, Self.labCards) {
            #expect(vector.id == lab.id)
            let art = Self.art(lab)
            #expect(art.processKey.rawValue == vector.process, "\(vector.name)")
            #expect(abs(art.altitudeShare - vector.altitudeShare) < 0.001, "\(vector.name)")
            #expect((art.stickerOnRight ? "right" : "left") == vector.side, "\(vector.name)")
            #expect(abs(art.stickerRotation - vector.stickerRotationDeg) < 0.01, "\(vector.name)")
            Self.expectClose(OKLab.toSRGB(art.titleInk), vector.titleInk, "\(vector.name) title")
            Self.expectClose(art.rgb(u: 0.5, v: 0.5), vector.fieldAtCenter, "\(vector.name) centre")
            Self.expectClose(art.rgb(u: 0.5, v: 0.06), vector.fieldAtTop, "\(vector.name) top")
        }
    }

    @Test func artIsDeterministic() {
        let card = Self.kenya
        #expect(CardArt.make(card, ink: nil) == CardArt.make(card, ink: nil))
        let file = StampFile(style: .auto, stamp: nil, scanRevision: "", pipelineVersion: InkStamp.pipelineVersion, manualRect: nil, inkRed: 0.2, inkGreen: 0.3, inkBlue: 0.8)
        #expect(CardArt.make(card, ink: file) == CardArt.make(card, ink: file))
        #expect(CardArt.make(card, ink: file) != CardArt.make(card, ink: nil))
    }

    // MARK: - Palette

    @Test func notesFindTheirAromaColour() {
        let palette = AromaPalette.shared
        #expect(palette.entry(forNote: "Winey Blueberry")?.id == "fruity-berry-blueberry")
        #expect(palette.entry(forNote: "Lemon Grass")?.id == "x-lemongrass")
        #expect(palette.entry(forNote: "Cacao Nibs")?.id == "nutty-cocoa-cocoa-chocolate")
        #expect(palette.entry(forNote: "Stonefruits")?.id == "x-stone-fruit")
        #expect(palette.entry(forNote: "Crisp Apple")?.id == "fruity-other-fruit-apple")
        #expect(palette.entry(forNote: "Quasar dust") == nil)
        #expect(palette.entry(forNote: "") == nil)
    }

    @Test func processAndAltitudeAreRead() {
        #expect(Terroir.classify(process: "Double Anaerobic") == .anaerobic)
        #expect(Terroir.classify(process: "Wet-hulled") == .wetHulled)
        #expect(Terroir.classify(process: "Pulped Natural") == .honey)
        #expect(Terroir.classify(process: "Sun dried natural") == .natural)
        #expect(Terroir.classify(process: "Lavé") == .washed)
        #expect(Terroir.classify(process: "") == .unknown)
        #expect(Terroir.altitudeMeters("1800-1900") == 1850)
        #expect(Terroir.altitudeMeters("1 800 masl") == 1800)
        #expect(Terroir.altitudeMeters("high") == nil)
        #expect(Terroir.altitudeShare("") == 0.5)
        #expect(Terroir.altitudeShare("900") == 0)
        #expect(Terroir.altitudeShare("2400") == 1)
    }

    // MARK: - Fallbacks

    @Test func withoutNotesTheFieldTakesTheGround() {
        var card = Self.kenya
        card.tastingNotes = []
        let art = CardArt.make(card, ink: nil)
        let land = Terroir.land(iso: "KE")
        #expect(!art.hasAromaNotes)
        #expect(art.fieldColors[0] == OKLab.fromHex(land.tone1))
        #expect(art.fieldColors[1] == OKLab.fromHex(land.tone2))
    }

    @Test func withoutCountryTheGroundIsNeutral() {
        var card = Self.kenya
        card.country = ""
        let art = CardArt.make(card, ink: nil)
        #expect(art.iso == nil)
        #expect(art.blobs[0].lab == OKLab.fromHex(Terroir.document.unknownOrigin.ground))
    }

    @Test func emptyNameTakesTheDisplayName() {
        var card = Self.kenya
        card.name = ""
        card.region = "Geera, Jimma"
        card.country = "Ethiopia"
        card.producer = ""
        let content = KohiCardContent.make(card)
        #expect(content.title == card.displayName)
        #expect(!content.title.isEmpty)
    }

    // MARK: - Stickers

    @Test func everyOriginAndSealHasItsSticker() {
        let codes = OriginCode.allCodes
        #expect(codes.count == 42)
        for code in codes {
            #expect(UIImage(named: "Stickers/origin-\(code.lowercased())") != nil, "origin \(code)")
        }
        let seals = Terroir.ProcessKey.allCases.compactMap(\.sealKey)
        #expect(seals.count == 5)
        for seal in seals {
            #expect(UIImage(named: "Stickers/seal-\(seal)") != nil, "seal \(seal)")
        }
    }

    @Test func oneCountryOneSticker() {
        var other = Self.kenya
        other.name = "Kiamugumo AA"
        other.process = "Natural"
        #expect(OriginStickerImage.assetName(for: Self.kenya) == "Stickers/origin-ke")
        #expect(OriginStickerImage.assetName(for: other) == OriginStickerImage.assetName(for: Self.kenya))

        var sealed = Self.kenya
        sealed.country = ""
        #expect(OriginStickerImage.assetName(for: sealed) == "Stickers/seal-washed")
        sealed.process = ""
        #expect(OriginStickerImage.assetName(for: sealed) == nil)
    }

    // MARK: - Backdrop

    @Test func theBackdropIsTheSameEveryTime() throws {
        let art = CardArt.make(Self.kenya, ink: nil)
        let size = CGSize(width: 360, height: 450)
        let first = try #require(CardBackdrop.render(art, mark: nil, treatment: .none, size: size))
        let second = try #require(CardBackdrop.render(art, mark: nil, treatment: .none, size: size))
        #expect(first.image.width == 360)
        #expect(first.image.height == 450)
        #expect(ImageCodec.encodePNG(first.image) == ImageCodec.encodePNG(second.image))
        let field = try #require(CardBackdrop.field(art, size: size))
        #expect(field.width == 360)
    }

    @Test func everyTreatmentDrawsSomething() throws {
        let mask = try #require(Self.fixture("klover"))
        let soft = try #require(MarkMask.antialiased(mask))
        let shape = try #require(MarkVectorizer.vectorize(soft))
        let art = CardArt.make(Self.kenya, ink: nil)
        let size = CGSize(width: 270, height: 338)
        let bare = try #require(CardBackdrop.render(art, mark: nil, treatment: .none, size: size))
        for treatment in [SymbolTreatment.emboss, .ink, .halftone, .pattern] {
            for mark in [MarkSource.shape(shape), .bitmap(soft)] {
                let drawn = try #require(CardBackdrop.render(art, mark: mark, treatment: treatment, size: size))
                #expect(ImageCodec.encodePNG(drawn.image) != ImageCodec.encodePNG(bare.image), "\(treatment)")
            }
        }
        let split = try #require(CardBackdrop.render(art, mark: .shape(shape), treatment: .emboss, size: size, separateEmbossEdges: true))
        #expect(split.edges != nil)
    }

    // MARK: - Vectorisation

    @Test func realMarksVectoriseCleanly() throws {
        for name in ["klover", "peru-angel", "panama", "blue-bottle"] {
            let mask = try #require(Self.fixture(name), "\(name)")
            let soft = try #require(MarkMask.antialiased(mask), "\(name)")
            #expect(max(soft.width, soft.height) >= 2 * max(mask.width, mask.height) || max(soft.width, soft.height) >= 512)
            let shape = try #require(MarkVectorizer.vectorize(soft), "\(name)")
            #expect(shape.pointCount < MarkVectorizer.maxPoints, "\(name): \(shape.pointCount)")
            let iou = Self.iou(shape, against: soft)
            #expect(iou >= 0.95, "\(name): IoU \(iou)")
        }
    }

    @Test func holesStayHoles() throws {
        for name in ["klover", "panama"] {
            let mask = try #require(Self.fixture(name))
            let soft = try #require(MarkMask.antialiased(mask))
            let shape = try #require(MarkVectorizer.vectorize(soft))
            #expect(shape.contours.count > 1, "\(name) lost its holes")
            let raster = Self.rasterAlpha(shape, width: soft.width, height: soft.height)
            let source = MarkMask.alpha(of: soft)
            var holePixels = 0
            var filledHoles = 0
            for i in source.indices where source[i] < 40 {
                if Self.insideOuterBox(i, width: soft.width, alpha: source) {
                    holePixels += 1
                    if raster[i] > 200 { filledHoles += 1 }
                }
            }
            #expect(holePixels > 0)
            #expect(Double(filledHoles) / Double(max(holePixels, 1)) < 0.05, "\(name): holes filled")
        }
    }

    @Test func emptyOrSpeckledMasksGiveNoShape() throws {
        let empty = try #require(MarkMask.rgba(width: 256, height: 256)?.makeImage())
        #expect(MarkVectorizer.vectorize(empty) == nil)

        let ctx = try #require(MarkMask.rgba(width: 512, height: 512))
        ctx.setFillColor(CGColor(srgbRed: 0.1, green: 0.1, blue: 0.1, alpha: 1))
        var rnd = Mulberry32(seed: 7)
        for _ in 0..<600 {
            ctx.fill(CGRect(x: Int(rnd.unit() * 510), y: Int(rnd.unit() * 510), width: 2, height: 2))
        }
        #expect(MarkVectorizer.vectorize(try #require(ctx.makeImage())) == nil)
    }

    // MARK: - Symbol style

    @Test func autoPicksATreatmentFromTheMark() {
        let tiny = InkStamp.Metrics(coverage: 0.4, areaRatio: 0.01, components: 2, cropLongSide: 400)
        let shortCrop = InkStamp.Metrics(coverage: 0.4, areaRatio: 0.1, components: 2, cropLongSide: 120)
        let line = InkStamp.Metrics(coverage: 0.2, areaRatio: 0.1, components: 2, cropLongSide: 400)
        let solid = InkStamp.Metrics(coverage: 0.4, areaRatio: 0.1, components: 2, cropLongSide: 400)
        #expect(SymbolRule.auto(tiny, draw: 0.1) == .pattern)
        #expect(SymbolRule.auto(shortCrop, draw: 0.1) == .pattern)
        #expect(SymbolRule.auto(line, draw: 0.5) == .emboss)
        #expect(SymbolRule.auto(line, draw: 0.6) == .ink)
        #expect(SymbolRule.auto(solid, draw: 0.59) == .emboss)
        #expect(SymbolRule.auto(solid, draw: 0.61) == .halftone)

        let library = StampFile(
            style: .emboss,
            stamp: InkStamp(rect: .zero, placement: .sticker, source: .library, version: 3, metrics: solid),
            scanRevision: "", pipelineVersion: 3, manualRect: nil
        )
        #expect(library.treatment(draw: 0.1) == .none)
    }

    @Test func briefSevenFilesStillDecode() throws {
        let json = """
        {"style":"sticker","scanRevision":"12-3","pipelineVersion":2,
         "manualRect":[[0.1,0.2],[0.3,0.4]],
         "stamp":{"rect":[[0.1,0.2],[0.3,0.4]],"placement":"sticker","source":"manual","version":2,
                  "metrics":{"coverage":0.2,"areaRatio":0.1,"components":3}}}
        """
        let sticker = try JSONDecoder().decode(StampFile.self, from: Data(json.utf8))
        #expect(sticker.style == .auto)
        #expect(sticker.manualRect == CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4))
        #expect(sticker.vectorVersion == nil)
        #expect(sticker.pipelineVersion != InkStamp.pipelineVersion)

        let watermark = try JSONDecoder().decode(
            StampFile.self, from: Data(json.replacingOccurrences(of: "\"sticker\",\"scan", with: "\"watermark\",\"scan").utf8)
        )
        #expect(watermark.style == .emboss)
    }

    // MARK: - Standard

    @Test func aFreshInstallOpensOnKohiCards() {
        let defaults = Self.freshDefaults()
        #expect(CardLookStore(defaults: defaults).global == .kohi)
        #expect(defaults.integer(forKey: CardStandard.lookMigrationKey) == CardStandard.lookVersion)
    }

    @Test func scanAsDefaultMovesOnceAndOverridesStay() {
        let defaults = Self.freshDefaults()
        let kept = UUID()
        let old = CardLookStore(defaults: defaults)
        old.setOverride(.scan, for: kept)
        defaults.set(CardLook.scan.rawValue, forKey: CardLookStore.globalKey)
        defaults.removeObject(forKey: CardStandard.lookMigrationKey)

        let migrated = CardLookStore(defaults: defaults)
        #expect(migrated.global == .kohi)
        #expect(migrated.resolved(cardID: kept, hasScan: true) == .scan)
        #expect(migrated.resolved(cardID: UUID(), hasScan: true) == .kohi)

        migrated.global = .scan
        #expect(CardLookStore(defaults: defaults).global == .scan)
    }

    @Test func theArchiveIsRedrawnOnceAndResumes() async {
        let defaults = Self.freshDefaults()
        let composer = CardComposer()
        composer.defaults = defaults
        let cards = (0..<5).map { i in
            CoffeeCard(name: "Lot \(i)", roaster: "Kohi", country: ["Kenya", "Peru", "", "Ethiopia", "Brazil"][i],
                       process: ["Washed", "Natural", "Honey", "", "Anaerobic"][i],
                       tastingNotes: i.isMultiple(of: 2) ? ["Blackcurrant"] : [])
        }
        defer { cards.forEach { ImageStore.shared.removeAll(for: $0.id) } }
        let library = StampLibrary()
        let regeneration = CardRegeneration()

        #expect(!CardStandard.isCurrent(defaults))
        let first = await regeneration.run(cards, library: library, defaults: defaults, composer: composer, limit: 3)
        #expect(first == 3)
        #expect(!CardStandard.isCurrent(defaults))

        let second = await regeneration.run(cards, library: library, defaults: defaults, composer: composer)
        #expect(second == 2)
        #expect(CardStandard.isCurrent(defaults))
        for card in cards {
            #expect(CardFiles.kohiTileNames(card.id).count == 1)
            #expect(CardRegeneration.isDone(card, composer: composer))
        }

        composer.resetCountForTesting()
        let third = await regeneration.run(cards, library: library, defaults: defaults, composer: composer)
        #expect(third == 0)
        #expect(composer.renderCount == 0)
    }

    @Test func theVisibleCardsGoFirst() {
        let now = Date()
        let cards = (0..<15).map { i in
            CoffeeCard(name: "\(i)", createdAt: now.addingTimeInterval(Double(i)))
        }
        let order = CardRegeneration.order(cards, visible: 12)
        #expect(Array(order.prefix(12).map(\.name)) == (0..<12).map(String.init))
        #expect(order.suffix(3).map(\.name) == ["14", "13", "12"])
    }

    @Test func aTileIsTheSameFileEveryTime() async throws {
        let defaults = Self.freshDefaults()
        let composer = CardComposer()
        composer.defaults = defaults
        let card = Self.kenya
        defer { ImageStore.shared.removeAll(for: card.id) }
        ImageStore.shared.removeAll(for: card.id)

        _ = try #require(await composer.tile(for: card))
        let url = CardFiles.kohiTile(id: card.id, token: composer.token(for: card))
        let first = try Data(contentsOf: url)

        composer.clearMemoryForTesting()
        try FileManager.default.removeItem(at: url)
        _ = try #require(await composer.tile(for: card))
        #expect(try Data(contentsOf: url) == first)
    }

    @Test func theMosaicGetsASmallCopyWithoutRenderingAgain() async throws {
        let defaults = Self.freshDefaults()
        let composer = CardComposer()
        composer.defaults = defaults
        let card = Self.kenya
        ImageStore.shared.removeAll(for: card.id)
        defer { ImageStore.shared.removeAll(for: card.id) }

        #expect(await composer.cachedDisplayTile(for: card, maxPixel: 600) == nil)
        let first = try #require(await composer.displayTile(for: card, maxPixel: 600))
        #expect(max(first.width, first.height) == 600)
        #expect(composer.renderCount == 1)

        composer.clearMemoryForTesting()
        let again = try #require(await composer.cachedDisplayTile(for: card, maxPixel: 600))
        #expect(again.height == 600)
        await composer.ensureTile(for: card)
        #expect(composer.renderCount == 1)
    }

    @Test func aLayoutChangeIsANewTile() {
        let defaults = Self.freshDefaults()
        let composer = CardComposer()
        composer.defaults = defaults
        let label = composer.token(for: Self.kenya)
        defaults.set(CardLayout.fullBleed.rawValue, forKey: CardLayout.defaultsKey)
        #expect(composer.token(for: Self.kenya) != label)
    }

    @Test func cardTitlesDropLatinAccentsOnly() {
        #expect(KohiCard.titleText("Diego Samuel Bermúdez, Piendamó") == "Diego Samuel Bermudez, Piendamo")
        #expect(KohiCard.titleText("Fazenda Sertão") == "Fazenda Sertao")
        #expect(KohiCard.titleText("レギュラーコーヒー") == "レギュラーコーヒー")
        #expect(KohiCard.titleText("Nano Challa") == "Nano Challa")
    }

    @Test func aCoffeeCanKeepItsOwnLayout() {
        let defaults = Self.freshDefaults()
        let composer = CardComposer()
        composer.defaults = defaults
        let store = CardLookStore(defaults: defaults)
        let other = UUID()
        let label = composer.token(for: Self.kenya)

        store.setLayout(.fullBleed, for: Self.kenya.id)
        #expect(store.layout(for: Self.kenya.id) == .fullBleed)
        #expect(store.layout(for: other) == .label)
        #expect(CardLayout.stored(for: Self.kenya.id, defaults) == .fullBleed)
        #expect(composer.token(for: Self.kenya) != label)
        #expect(CardLookStore(defaults: defaults).layout(for: Self.kenya.id) == .fullBleed)

        store.setLayout(.label, for: Self.kenya.id)
        #expect(store.layoutOverrides[Self.kenya.id] == nil)
        #expect(composer.token(for: Self.kenya) == label)
    }

    // MARK: - Fixtures

    static func freshDefaults() -> UserDefaults {
        let name = "DevBrief9Tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    static func fixture(_ name: String) -> CGImage? {
        let url = repoRoot.appending(path: "docs/card-lab/fixtures/marks/\(name).png")
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    static func rasterAlpha(_ shape: MarkShape, width: Int, height: Int) -> [UInt8] {
        guard let image = SymbolLayer.rasterized(.shape(shape), width: width, height: height) else { return [] }
        return MarkMask.alpha(of: image)
    }

    static func iou(_ shape: MarkShape, against mask: CGImage) -> Double {
        let raster = rasterAlpha(shape, width: mask.width, height: mask.height)
        let source = MarkMask.alpha(of: mask)
        guard raster.count == source.count else { return 0 }
        var inter = 0, union = 0
        for i in source.indices {
            let a = source[i] >= 128, b = raster[i] >= 128
            if a && b { inter += 1 }
            if a || b { union += 1 }
        }
        return union == 0 ? 0 : Double(inter) / Double(union)
    }

    /// A clear pixel with ink on its row both left and right, and on its column above and below.
    static func insideOuterBox(_ i: Int, width: Int, alpha: [UInt8]) -> Bool {
        let height = alpha.count / width
        let x = i % width, y = i / width
        func ink(_ x: Int, _ y: Int) -> Bool { alpha[y * width + x] > 200 }
        let left = (0..<x).contains { ink($0, y) }
        let right = ((x + 1)..<width).contains { ink($0, y) }
        let up = (0..<y).contains { ink(x, $0) }
        let down = ((y + 1)..<height).contains { ink(x, $0) }
        return left && right && up && down
    }

    static let kenya: CoffeeCard = {
        var card = CoffeeCard(
            id: UUID(uuidString: "5c1d9f02-3b8e-41f7-8d2c-6a4e0f9b7c12")!,
            name: "Kenya Tekangu",
            roaster: "Coffee Collective"
        )
        card.country = "Kenya"
        card.region = "Nyeri"
        card.altitude = "1800"
        card.process = "Washed"
        card.roastLevel = .light
        card.tastingNotes = ["Floral", "Red Currant", "Vanilla"]
        return card
    }()

    static func expectClose(_ rgb: (Double, Double, Double), _ hex: String, _ label: String) {
        guard let want = OKLab.rgb(hex: hex) else {
            Issue.record("bad hex \(hex)")
            return
        }
        let got = [rgb.0, rgb.1, rgb.2].map { ($0 * 255).rounded() }
        let ref = [want.0, want.1, want.2].map { ($0 * 255).rounded() }
        for (g, r) in zip(got, ref) {
            #expect(abs(g - r) <= 2, "\(label): \(got) vs \(ref)")
        }
    }

    static var repoRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }
}
