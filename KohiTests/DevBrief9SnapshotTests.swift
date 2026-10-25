import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import Testing
@testable import Kohi

/// Six coffees of the card lab, each as a tile and a fiche, in both layouts.
@Suite(.serialized)
@MainActor
struct DevBrief9SnapshotTests {
    private struct Sample {
        var card: CoffeeCard
        var mark: String?
        var treatment: SymbolTreatment
    }

    @Test(arguments: ["nano-challa", "chelbesa", "el-paraiso", "gallardo", "three-africas", "fazenda-sertao"])
    func kohiCards(_ key: String) throws {
        let sample = try #require(Self.samples[key])
        for density in [CardDensity.tile, .detail] {
            for layout in [CardLayout.label, .fullBleed] {
                SnapshotSupport.image(
                    of: try Self.card(sample, density: density, layout: layout),
                    width: Self.width(density) + 32,
                    height: Self.width(density) / CardTileLayout.aspectRatio + 32,
                    named: "\(key)-\(density.rawValue)-\(layout.rawValue)"
                )
            }
        }
    }

    @Test func placeholderIsTheFieldAlone() throws {
        let sample = try #require(Self.samples["el-paraiso"])
        SnapshotSupport.image(
            of: KohiCardPlaceholder(card: sample.card, width: 360).padding(16),
            width: 392,
            height: 482,
            named: "placeholder"
        )
    }

    // MARK: - Fixtures

    private static func width(_ density: CardDensity) -> CGFloat {
        density == .tile ? 360 : 353
    }

    private static func card(_ sample: Sample, density: CardDensity, layout: CardLayout) throws -> some View {
        let width = width(density)
        let art = CardArt.make(sample.card, ink: nil)
        let content = KohiCardContent.make(sample.card, art: art)
        let mark = try sample.mark.map { try MarkSource.shape(shape($0)) }
        let size = CGSize(width: width * 3, height: (width / CardTileLayout.aspectRatio * 3).rounded())
        let rendered = try #require(CardBackdrop.render(
            art, mark: mark, treatment: mark == nil ? .none : sample.treatment, size: size,
            separateEmbossEdges: density == .detail
        ))
        return KohiCard(
            content: content,
            density: density,
            width: width,
            layout: layout,
            backdrop: rendered.image,
            textTone: rendered.textTone,
            edges: rendered.edges
        )
        .padding(16)
    }

    private static var shapes: [String: MarkShape] = [:]

    private static func shape(_ name: String) throws -> MarkShape {
        if let hit = shapes[name] { return hit }
        let url = DevBrief9Tests.repoRoot.appending(path: "docs/card-lab/fixtures/marks/\(name).png")
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let mask = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let soft = try #require(MarkMask.antialiased(mask))
        let shape = try #require(MarkVectorizer.vectorize(soft))
        shapes[name] = shape
        return shape
    }

    private static let roasted = Date(timeIntervalSince1970: 1_790_000_000)

    private static let samples: [String: Sample] = [
        "nano-challa": Sample(
            card: CoffeeCard(
                id: UUID(uuidString: "0b6e2c1a-7d4f-4e8a-9a51-3c2f8e6b1d01")!,
                name: "Nano Challa", roaster: "Klover Coffee Paris", country: "Ethiopia", region: "Geera, Jimma",
                altitude: "2048", variety: "Heirloom", process: "Washed",
                tastingNotes: ["Floral", "Citrus", "Stonefruits"], roastLevel: .light, roastedOn: roasted,
                date: roasted, createdAt: roasted
            ),
            mark: "klover", treatment: .emboss
        ),
        "chelbesa": Sample(
            card: CoffeeCard(
                id: UUID(uuidString: "9a7e3c44-1f2b-4d6e-b0a8-2e5c7d9f1a23")!,
                name: "Chelbesa", country: "Ethiopia", region: "Gedeb, Gedeo", altitude: "2050",
                variety: "Heirloom Landrace", process: "Natural",
                tastingNotes: ["Blueberry", "Jasmine", "Cane Sugar"], roastLevel: .light,
                date: roasted, createdAt: roasted
            ),
            mark: nil, treatment: .none
        ),
        "el-paraiso": Sample(
            card: CoffeeCard(
                id: UUID(uuidString: "e2f4a6b8-c0d2-4e6f-8a0b-1c3d5e7f9a34")!,
                name: "El Paraíso Lychee", roaster: "Manhattan", country: "Colombia", region: "Piendamó, Cauca",
                altitude: "1930", variety: "Castillo", process: "Double Anaerobic",
                tastingNotes: ["Lychee", "Rose", "Passionfruit"], roastLevel: .light,
                date: roasted, createdAt: roasted
            ),
            mark: nil, treatment: .none
        ),
        "gallardo": Sample(
            card: CoffeeCard(
                id: UUID(uuidString: "1a3c5e7b-9d1f-4b3d-a5e7-9c1e3a5b7d78")!,
                name: "Gallardo Family", country: "Panama",
                date: roasted, createdAt: roasted
            ),
            mark: "panama", treatment: .pattern
        ),
        "three-africas": Sample(
            card: CoffeeCard(
                id: UUID(uuidString: "f6b8d0e2-4a6c-4e8a-b0c2-4d6f8b0d2ef5")!,
                name: "Three Africas", roaster: "Blue Bottle",
                tastingNotes: ["Golden Raisin", "Winey Blueberry", "Lemon Zest"],
                date: roasted, createdAt: roasted
            ),
            mark: "blue-bottle", treatment: .halftone
        ),
        "fazenda-sertao": Sample(
            card: CoffeeCard(
                id: UUID(uuidString: "2f4b6d8e-0a2c-4e4f-a6b8-6f8b0d2f4a06")!,
                country: "Brazil", region: "Carmo de Minas, Minas Gerais",
                altitude: "1150", variety: "Yellow Bourbon", process: "Pulped Natural",
                tastingNotes: ["Hazelnut", "Milk Chocolate", "Almond"], farm: "Fazenda Sertão", roastLevel: .medium,
                date: roasted, createdAt: roasted
            ),
            mark: nil, treatment: .none
        ),
    ]
}
