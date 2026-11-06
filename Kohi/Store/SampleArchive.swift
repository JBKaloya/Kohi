import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import os

/// Bundled sample cards used on first launch and as a demo scan. The seed writes
/// through the real storage layout, so the grid, the thumbnail pipeline and the
/// detail view all exercise exactly the code path a genuine scan uses. There is
/// no mock branch anywhere in the views.
nonisolated enum SampleArchive {
    private struct Sample {
        let file: String
        let name: String
        let roaster: String
        let country: String
        let region: String
        let producer: String
        let altitude: String
        let variety: String
        let process: String
        let notes: [String]
        let brew: BrewMethod
        let daysAgo: Int
        let personal: String
    }

    private static let samples: [Sample] = [
        Sample(
            file: "kenya-tekangu",
            name: "Kenya Tekangu", roaster: "Coffee Collective",
            country: "Kenya", region: "Nyeri", producer: "Tekangu Cooperative",
            altitude: "1800m", variety: "AA Tekangu Ngunguru #101", process: "Washed",
            notes: ["Floral", "Red Currant", "Vanilla"], brew: .v60, daysAgo: 1,
            personal: "Blackcurrant hit harder at 94°C. Worth going coarser next time."
        ),
        Sample(
            file: "ethiopia-chelbesa",
            name: "Chelbesa", roaster: "Gardelli",
            country: "Ethiopia", region: "Gedeb, Gedeo", producer: "Chelbesa Washing Station",
            altitude: "2050m", variety: "Heirloom Landrace", process: "Natural",
            notes: ["Blueberry", "Jasmine", "Cane Sugar"], brew: .filter, daysAgo: 4,
            personal: "The one everybody at the table asked about."
        ),
        Sample(
            file: "colombia-el-paraiso",
            name: "El Paraíso Lychee", roaster: "Manhattan",
            country: "Colombia", region: "Piendamó, Cauca", producer: "Diego Samuel Bermúdez",
            altitude: "1930m", variety: "Castillo", process: "Double Anaerobic",
            notes: ["Lychee", "Rose", "Passionfruit"], brew: .aeropress, daysAgo: 9,
            personal: "Almost too much. Good once, not a bag."
        ),
        Sample(
            file: "guatemala-el-injerto",
            name: "El Injerto Pacamara", roaster: "Tim Wendelboe",
            country: "Guatemala", region: "La Libertad, Huehuetenango", producer: "Aguirre Family",
            altitude: "1650m", variety: "Pacamara", process: "Washed",
            notes: ["Toffee", "Orange", "Cocoa"], brew: .espresso, daysAgo: 15,
            personal: ""
        ),
        Sample(
            file: "panama-hartmann",
            name: "Hartmann Geisha", roaster: "La Cabra",
            country: "Panama", region: "Santa Clara, Volcán", producer: "Ratibor Hartmann",
            altitude: "1500m", variety: "Geisha", process: "Honey",
            notes: ["Peach", "Bergamot", "Honeysuckle"], brew: .v60, daysAgo: 23,
            personal: "Bergamot on the cool-down is unmistakable."
        ),
        Sample(
            file: "brazil-fazenda-sertao",
            name: "Fazenda Sertão", roaster: "Square Mile",
            country: "Brazil", region: "Carmo de Minas, Minas Gerais", producer: "Guimarães Family",
            altitude: "1150m", variety: "Yellow Bourbon", process: "Pulped Natural",
            notes: ["Hazelnut", "Milk Chocolate", "Almond"], brew: .espresso, daysAgo: 31,
            personal: "House espresso. Holds up in milk."
        ),
    ]

    /// True when there is no archive on disk yet.
    static var shouldSeed: Bool {
        !CardFileStore().exists
    }

    /// A bundled sample warped onto a surface, as though it had just been
    /// photographed at an angle. The quad is known exactly, so this exercises
    /// perspective correction, the cut-out, and OCR without a camera.
    static func sampleCapture() -> CapturedCard? {
        guard
            let name = samples.randomElement()?.file,
            let url = Bundle.main.url(forResource: name, withExtension: "png"),
            let card = ImageCodec.decode(url)
        else { return nil }
        return sampleCapture(image: card)
    }

    /// Lays `card` on a surface at a slight angle, as a photo of it would be.
    static func sampleCapture(image card: CGImage) -> CapturedCard? {
        let canvas = CGSize(width: 2400, height: 3200)
        let quad = Quad(
            topLeft: CGPoint(x: 470, y: 690),
            topRight: CGPoint(x: 1930, y: 540),
            bottomRight: CGPoint(x: 2040, y: 2560),
            bottomLeft: CGPoint(x: 380, y: 2430)
        )

        func flip(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x, y: canvas.height - point.y)
        }

        let warp = CIFilter.perspectiveTransform()
        warp.inputImage = CIImage(cgImage: card)
        warp.topLeft = flip(quad.topLeft)
        warp.topRight = flip(quad.topRight)
        warp.bottomRight = flip(quad.bottomRight)
        warp.bottomLeft = flip(quad.bottomLeft)

        let surface = CIImage(color: CIColor(red: 0.28, green: 0.22, blue: 0.17))
            .cropped(to: CGRect(origin: .zero, size: canvas))

        let composite = CIFilter.sourceOverCompositing()
        composite.inputImage = warp.outputImage
        composite.backgroundImage = surface

        guard
            let composited = composite.outputImage,
            let image = ImagePipeline.context.createCGImage(
                composited, from: CGRect(origin: .zero, size: canvas)
            )
        else { return nil }

        return CapturedCard(image: image, quad: quad)
    }

    static func seed() -> [CoffeeCard] {
        var cards: [CoffeeCard] = []
        for sample in samples {
            guard
                let url = Bundle.main.url(forResource: sample.file, withExtension: "png"),
                let image = ImageCodec.decode(url),
                let heic = ImageCodec.encodeHEIC(image, quality: 0.9)
            else {
                Log.app.error("missing sample \(sample.file)")
                continue
            }

            let id = UUID()
            let created = Calendar.current.date(
                byAdding: .day, value: -sample.daysAgo, to: .now
            ) ?? .now

            do {
                try ImageStore.shared.write(heic, for: id, kind: .flat)
                // The sample has no separate raw capture, so the flat image also
                // stands in as the original.
                try ImageStore.shared.write(heic, for: id, kind: .original)
            } catch {
                Log.app.error("could not seed \(sample.file): \(error)")
                continue
            }

            cards.append(
                CoffeeCard(
                    id: id,
                    name: sample.name,
                    roaster: sample.roaster,
                    country: sample.country,
                    region: sample.region,
                    producer: sample.producer,
                    altitude: sample.altitude,
                    variety: sample.variety,
                    process: sample.process,
                    tastingNotes: sample.notes,
                    brewMethod: sample.brew,
                    personalNotes: sample.personal,
                    date: created,
                    createdAt: created,
                    updatedAt: created,
                    aspectRatio: Double(image.width) / Double(image.height)
                )
            )
        }
        return cards
    }
}
