import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import Kohi

@Suite(.serialized)
@MainActor
struct DevBrief7Tests {
    @Test func originCodesFollowTheWhitelist() {
        #expect(OriginCode.alpha2(for: "Kenya") == "KE")
        #expect(OriginCode.alpha2(for: "Ethiopia") == "ET")
        #expect(OriginCode.alpha2(for: "Sumatra") == "ID")
        #expect(OriginCode.alpha2(for: "Java") == "ID")
        #expect(OriginCode.alpha2(for: "Sulawesi") == "ID")
        #expect(OriginCode.alpha2(for: "Hawaii") == "US")
        #expect(OriginCode.alpha2(for: "Papua New Guinea") == "PG")
        #expect(OriginCode.alpha2(for: "Congo") == nil)
        #expect(OriginCode.alpha2(for: "Timor") == nil)
        #expect(OriginCode.alpha2(for: "Atlantis") == nil)
        #expect(OriginCode.alpha2(for: "  ") == nil)
    }

    @Test func altitudeKeepsWordsAndGroupsABareNumber() {
        #expect(KohiCardContent.altitudeText("1800") == "1\u{202F}800 m")
        #expect(KohiCardContent.altitudeText("800") == "800 m")
        #expect(KohiCardContent.altitudeText("1650–1900 masl") == "1650–1900 masl")
        #expect(KohiCardContent.altitudeText("1800m") == "1800m")
        #expect(KohiCardContent.altitudeText("") == "")
    }

    @Test func cardShowsStoredFieldsAndDropsEmptyLines() {
        let full = KohiCardContent.make(Self.kenya)
        #expect(full.roaster == "Coffee Collective")
        #expect(full.title == "Kenya Tekangu")
        #expect(full.titleUsesSmallSize == false)
        #expect(full.place == "Nyeri, Kenya")
        #expect(full.altitude == "1\u{202F}800 m")
        #expect(full.process == "Washed")
        #expect(full.variety == "AA Tekangu Ngunguru #101")
        #expect(full.notes == ["Floral", "Red Currant", "Vanilla"])
        #expect(full.footer.hasPrefix("ROASTED "))
        #expect(full.footer.hasSuffix("FROM THE PACK"))

        let nameOnly = KohiCardContent.make(CoffeeCard(name: "Kenya Tekangu", createdAt: Self.added))
        #expect(nameOnly.roaster.isEmpty)
        #expect(nameOnly.place.isEmpty)
        #expect(nameOnly.notes.isEmpty)
        #expect(nameOnly.footer.hasPrefix("ADDED "))

        var long = Self.kenya
        long.name = "Ethiopia Nano Challa Lot Seven"
        #expect(KohiCardContent.make(long).titleUsesSmallSize)

        var noNotes = Self.kenya
        noNotes.tastingNotes = []
        #expect(KohiCardContent.make(noNotes).notes.isEmpty)

        var noRoaster = Self.kenya
        noRoaster.roaster = ""
        noRoaster.country = ""
        noRoaster.cuppingScore = nil
        #expect(KohiCardContent.make(noRoaster).roaster.isEmpty)
    }

    @Test func notesStayOnThePackAndStopAtThree() {
        var card = Self.kenya
        card.tastingNotes = ["One", "Two", "Three", "Four"]
        card.personalNotes = "not on the card"
        #expect(KohiCardContent.make(card).notes == ["One", "Two", "Three"])
        #expect(!KohiCardContent.make(card).footer.contains("not on the card"))
    }

    @Test func tastingFlavoursFillEmptyPackNotesAndStopAtThree() {
        var card = CoffeeCard(name: "House")
        card.tastings = [
            Tasting(
                context: .home(brewID: nil),
                flavors: [FlavorTag(id: "fruity-berry-blueberry"), FlavorTag(id: "floral")]
            ),
        ]
        #expect(KohiCardContent.make(card).notes == ["Blueberry", "Floral"])

        card.tastingNotes = ["One", "Two", "Three"]
        #expect(KohiCardContent.make(card).notes == ["One", "Two", "Three"])
    }

    @Test func theTitleTakesTheFirstNoteAndOtherwiseTheGround() {
        let card = CoffeeCard(name: "Kenya", tastingNotes: ["Blueberry"])
        let color = KohiCardContent.make(card)
        #expect(color.titleRed != nil)
        let floral = CoffeeCard(name: "Kenya", tastingNotes: ["Floral"])
        let other = KohiCardContent.make(floral)
        #expect(color.titleGreen != other.titleGreen)
        #expect(KohiCardContent.make(CoffeeCard(name: "Kenya")).titleRed != nil)
    }

    @Test func lookDefaultsToKohiAndAMissingScanFallsBack() {
        let defaults = UserDefaults(suiteName: "kohi-look-\(UUID().uuidString)")!
        let store = CardLookStore(defaults: defaults)
        let id = UUID()
        #expect(store.global == .kohi)
        #expect(store.resolved(cardID: id, hasScan: true) == .kohi)
        #expect(store.resolved(cardID: id, hasScan: false) == .kohi)

        store.global = .scan
        #expect(store.resolved(cardID: id, hasScan: true) == .scan)
        store.global = .kohi
        #expect(store.resolved(cardID: id, hasScan: true) == .kohi)

        store.setOverride(.scan, for: id)
        #expect(store.resolved(cardID: id, hasScan: true) == .scan)
        #expect(store.resolved(cardID: id, hasScan: false) == .kohi)

        let again = CardLookStore(defaults: defaults)
        #expect(again.global == .kohi)
        #expect(again.resolved(cardID: id, hasScan: true) == .scan)
    }

    @Test func editingTheRegionChangesTheCacheToken() {
        let first = KohiCardContent.make(Self.kenya).cacheToken(symbol: "", layout: .label, density: .tile)
        var edited = Self.kenya
        edited.region = "Kirinyaga"
        let second = KohiCardContent.make(edited).cacheToken(symbol: "", layout: .label, density: .tile)
        let same = KohiCardContent.make(Self.kenya).cacheToken(symbol: "", layout: .label, density: .tile)
        #expect(first != second)
        #expect(first == same)
        let stamped = KohiCardContent.make(Self.kenya).cacheToken(symbol: "emboss|3", layout: .label, density: .tile)
        #expect(stamped != first)
    }

    @Test func stampGatesRejectSlabsNoiseAndWords() {
        let fine = InkStamp.Metrics(coverage: 0.12, areaRatio: 0.15, components: 4)
        #expect(InkStampGates.accepted(fine, words: []))
        #expect(InkStampGates.accepted(fine, words: ["OK", "A"]))
        #expect(!InkStampGates.accepted(fine, words: ["THE"]))
        #expect(!InkStampGates.accepted(InkStamp.Metrics(coverage: 0.8, areaRatio: 0.15, components: 1), words: []))
        #expect(!InkStampGates.accepted(InkStamp.Metrics(coverage: 0.01, areaRatio: 0.15, components: 1), words: []))
        #expect(!InkStampGates.accepted(InkStamp.Metrics(coverage: 0.12, areaRatio: 0.02, components: 1), words: []))
        #expect(!InkStampGates.accepted(InkStamp.Metrics(coverage: 0.12, areaRatio: 0.7, components: 1), words: []))
        #expect(!InkStampGates.accepted(InkStamp.Metrics(coverage: 0.12, areaRatio: 0.15, components: 400), words: []))
        #expect(InkStampGates.placement(areaRatio: 0.25, coverage: 0.1) == .watermark)
        #expect(InkStampGates.placement(areaRatio: 0.1, coverage: 0.3) == .watermark)
        #expect(InkStampGates.placement(areaRatio: 0.1, coverage: 0.1) == .sticker)
    }

    @Test func aSparseOutlineBecomesAStampAndASlabDoesNot() {
        let sticker = InkStampPipeline.draw(scan: Self.outline(box: 90, stroke: 6, canvas: 256))
        #expect(sticker != nil)
        #expect(sticker?.placement == .sticker)

        let watermark = InkStampPipeline.draw(scan: Self.outline(box: 170, stroke: 6, canvas: 256))
        #expect(watermark != nil)
        #expect(watermark?.placement == .watermark)

        #expect(InkStampPipeline.draw(scan: Self.filled(canvas: 128)) == nil)
    }

    @Test func aPhotographPrefersEdgesAndAFlatPackDoesNot() {
        #expect(InkStampPipeline.prefersEdgeWork(Self.noise(canvas: 96)))
        #expect(!InkStampPipeline.prefersEdgeWork(Self.outline(box: 40, stroke: 4, canvas: 96)))
    }

    @Test func cardRenderingDoesNotCallTheNetwork() throws {
        let root = BrewJourneySupport.kohiRoot()
        let files = [
            "Design/KohiCard.swift",
            "Process/CardComposer.swift",
            "Process/InkStampPipeline.swift",
            "Process/KohiCardContent.swift",
            "Process/CardFiles.swift",
            "Process/CardArt.swift",
            "Process/MarkVectorizer.swift",
            "Design/CardBackdrop.swift",
            "Design/SymbolLayer.swift",
            "Design/OriginStickerImage.swift",
            "App/CardStandard.swift",
        ]
        for file in files {
            let text = try String(contentsOf: root.appending(path: file), encoding: .utf8)
            #expect(!text.contains("URLSession"))
            #expect(!text.contains("Supabase"))
        }
    }

    /// Written before the pack photos exist. A stamp that comes back must pass the gates,
    /// including the three-letter word check. No stamp is a valid card.
    /// Files, when they land: `KohiTests/Fixtures/Packs/{industra,ayla,brut,tribute,burned}`.
    @Test(.enabled(if: DevBrief7Tests.packFixturesPresent, "Pack photos are not in the repo."))
    func realPacksStayInsideTheGates() async throws {
        for name in Self.packNames {
            let image = try #require(Self.packImage(name))
            guard let drawing = InkStampPipeline.draw(scan: image) else { continue }
            let lines = await TextExtractor.read(image: drawing.image)
            let words = lines.flatMap { InkStampGates.words(in: $0.text) }
            #expect(InkStampGates.accepted(drawing.metrics, words: words), "\(name) left the gates")
        }
    }

    @Test func aSecondOpenDoesNotRenderAgain() async {
        let id = UUID()
        defer { ImageStore.shared.removeAll(for: id) }
        var card = Self.kenya
        card = CoffeeCard(
            id: id,
            name: card.name,
            roaster: card.roaster,
            country: card.country,
            region: card.region,
            altitude: card.altitude,
            variety: card.variety,
            process: card.process,
            tastingNotes: card.tastingNotes,
            roastedOn: card.roastedOn,
            cuppingScore: card.cuppingScore,
            createdAt: card.createdAt
        )
        CardComposer.shared.resetCountForTesting()
        let before = CardComposer.shared.renderCount
        let first = await CardComposer.shared.tile(for: card)
        #expect(first != nil)
        let drawn = CardComposer.shared.renderCount
        #expect(drawn == before + 1)
        _ = await CardComposer.shared.tile(for: card)
        #expect(CardComposer.shared.renderCount == drawn)

        card.region = "Kirinyaga"
        _ = await CardComposer.shared.tile(for: card)
        #expect(CardComposer.shared.renderCount == drawn + 1)
    }

    nonisolated private static let packNames = ["industra", "ayla", "brut", "tribute", "burned"]

    nonisolated static var packFixturesPresent: Bool {
        packNames.allSatisfy { packURL($0) != nil }
    }

    nonisolated private static func packURL(_ name: String) -> URL? {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "Fixtures/Packs")
        for ext in ["jpg", "jpeg", "heic", "png"] {
            let url = dir.appending(path: "\(name).\(ext)")
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    private static func packImage(_ name: String) -> CGImage? {
        guard let url = packURL(name),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private static var added: Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 12))!
    }

    private static var roasted: Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 12))!
    }

    private static var kenya: CoffeeCard {
        CoffeeCard(
            id: UUID(uuidString: "7E0B6C1A-3D2F-4B8E-9A51-2C4D6E8F0A13")!,
            name: "Kenya Tekangu",
            roaster: "Coffee Collective",
            country: "Kenya",
            region: "Nyeri",
            altitude: "1800",
            variety: "AA Tekangu Ngunguru #101",
            process: "Washed",
            tastingNotes: ["Floral", "Red Currant", "Vanilla"],
            roastedOn: roasted,
            cuppingScore: 87,
            createdAt: added
        )
    }

    private static func outline(box: CGFloat, stroke: CGFloat, canvas: Int) -> CGImage {
        let ctx = context(canvas)
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: canvas, height: canvas))
        ctx.setStrokeColor(CGColor(gray: 0, alpha: 1))
        ctx.setLineWidth(stroke)
        let origin = (CGFloat(canvas) - box) / 2
        ctx.stroke(CGRect(x: origin, y: origin, width: box, height: box))
        return ctx.makeImage()!
    }

    private static func filled(canvas: Int) -> CGImage {
        let ctx = context(canvas)
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: canvas, height: canvas))
        return ctx.makeImage()!
    }

    private static func noise(canvas: Int) -> CGImage {
        let ctx = context(canvas)
        var rng = SplitMix(seed: 42)
        for y in 0..<canvas {
            for x in 0..<canvas {
                let gray = CGFloat(rng.next() % 256) / 255
                ctx.setFillColor(CGColor(gray: gray, alpha: 1))
                ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        return ctx.makeImage()!
    }

    private static func context(_ canvas: Int) -> CGContext {
        CGContext(
            data: nil,
            width: canvas,
            height: canvas,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
    }

    private struct SplitMix {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }
}
