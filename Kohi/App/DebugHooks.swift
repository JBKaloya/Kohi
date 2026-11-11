#if DEBUG
import Foundation

/// Launch-time switches used while building the app, set through the simulator's
/// child environment:
///
///     SIMCTL_CHILD_KOHI_OPEN_FIRST=1   open the newest card on launch
///     SIMCTL_CHILD_KOHI_AUTOSCAN=1     file a sample scan on launch
///     SIMCTL_CHILD_KOHI_REVIEW=1       open the scan flow on the review step
///     SIMCTL_CHILD_KOHI_EMPTY=1        skip seeding, to see the empty state
///     SIMCTL_CHILD_KOHI_MIGRATION_REPORT=1  log the lot 2 archive report after migrate
///     SIMCTL_CHILD_KOHI_FAKE_FIX=48.8638,2.3480,20   stand there (lat,lon,accuracy m);
///                                     also `-kohi.fakeFix 48.8638,2.3480,20`
///     SIMCTL_CHILD_KOHI_DEMO=bag|card|menu  the simulator shutter files that demo
///     SIMCTL_CHILD_KOHI_KEYBOARD=sheet|after  open Steps over the grid, or from
///                                     It's done, with the last step's At focused
///
/// Debug builds only. There is no settings screen and this is not one.
nonisolated enum DebugHooks {
    static var opensFirstCard: Bool { flag("KOHI_OPEN_FIRST") }
    static var autoScans: Bool { flag("KOHI_AUTOSCAN") }
    static var opensReview: Bool { flag("KOHI_REVIEW") }
    static var skipsSeed: Bool { flag("KOHI_EMPTY") }
    static var keyboardRepro: String? { ProcessInfo.processInfo.environment["KOHI_KEYBOARD"] }

    static var bulkSeedCount: Int? {
        ProcessInfo.processInfo.environment["KOHI_BULK"].flatMap(Int.init)
    }

    /// A pretend location, so the scan question can be tried at a desk. Either
    /// the launch argument `-kohi.fakeFix 48.8638,2.3480,20` or `KOHI_FAKE_FIX`.
    /// The accuracy defaults to 20 metres.
    static var fakeFix: (latitude: Double, longitude: Double, accuracy: Double)? {
        guard let raw = UserDefaults.standard.string(forKey: "kohi.fakeFix")
            ?? ProcessInfo.processInfo.environment["KOHI_FAKE_FIX"] else { return nil }
        let parts = raw.split(separator: ",").compactMap {
            Double($0.trimmingCharacters(in: .whitespaces))
        }
        guard parts.count >= 2 else { return nil }
        return (parts[0], parts[1], parts.count > 2 ? parts[2] : 20)
    }

    static func sampleCapture() -> CapturedCard? {
        SampleArchive.sampleCapture()
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
