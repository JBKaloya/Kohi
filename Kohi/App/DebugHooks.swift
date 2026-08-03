#if DEBUG
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// Launch-time switches used while building the app, set through the simulator's
/// child environment:
///
///     SIMCTL_CHILD_KOHI_OPEN_FIRST=1   open the newest card on launch
///     SIMCTL_CHILD_KOHI_AUTOSCAN=1     file a sample scan on launch
///     SIMCTL_CHILD_KOHI_REVIEW=1       open the scan flow on the review step
///     SIMCTL_CHILD_KOHI_BACK=1         open cards turned to their printed back
///     SIMCTL_CHILD_KOHI_EMPTY=1        skip seeding, to see the empty state
///     SIMCTL_CHILD_KOHI_BULK=400       seed N generated cards for a perf run
///
/// Debug builds only. There is no settings screen and this is not one.
nonisolated enum DebugHooks {
    static var opensFirstCard: Bool { flag("KOHI_OPEN_FIRST") }
    static var autoScans: Bool { flag("KOHI_AUTOSCAN") }
    static var opensReview: Bool { flag("KOHI_REVIEW") }
    static var showsCardBack: Bool { flag("KOHI_BACK") }
    static var skipsSeed: Bool { flag("KOHI_EMPTY") }

    static var bulkSeedCount: Int? {
        ProcessInfo.processInfo.environment["KOHI_BULK"].flatMap(Int.init)
    }

    static let sampleNames = [
        "kenya-tekangu", "ethiopia-chelbesa", "colombia-el-paraiso",
        "guatemala-el-injerto", "panama-hartmann", "brazil-fazenda-sertao",
    ]

    /// A bundled sample warped onto a surface, as though it had just been
    /// photographed at an angle. The quad is known exactly, so this exercises
    /// perspective correction and the cut-out for real without a camera.
    static func sampleCapture() -> CapturedCard? {
        guard
            let name = sampleNames.randomElement(),
            let url = Bundle.main.url(forResource: name, withExtension: "png"),
            let card = ImageCodec.decode(url)
        else { return nil }

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

    /// Inflates the archive to `count` cards for a scrolling run. The images are
    /// hard links to the seeded originals, so a few hundred cards cost a few
    /// hundred inodes rather than a few hundred megabytes. Thumbnails are still
    /// generated per card, which is the part being measured.
    static func bulkSeed(count: Int, from templates: [CoffeeCard]) -> [CoffeeCard] {
        guard !templates.isEmpty else { return [] }
        let store = ImageStore.shared
        var generated: [CoffeeCard] = []

        for index in 0..<count {
            let template = templates[index % templates.count]
            let id = UUID()

            do {
                try FileManager.default.createDirectory(
                    at: store.directory(for: id), withIntermediateDirectories: true
                )
                try FileManager.default.linkItem(
                    at: store.url(for: template.id, kind: .flat),
                    to: store.url(for: id, kind: .flat)
                )
            } catch {
                continue
            }

            let card = CoffeeCard(
                id: id,
                name: "\(template.name) \(index + 1)",
                roaster: template.roaster,
                country: template.country,
                region: template.region,
                producer: template.producer,
                altitude: template.altitude,
                variety: template.variety,
                process: template.process,
                tastingNotes: template.tastingNotes,
                brewMethod: template.brewMethod,
                date: .now,
                createdAt: Date(timeIntervalSinceNow: -Double(index) * 3600),
                updatedAt: .now,
                aspectRatio: template.aspectRatio
            )
            generated.append(card)
        }

        return generated
    }

    private static func flag(_ name: String) -> Bool {
        ProcessInfo.processInfo.environment[name] != nil
    }
}
#endif
