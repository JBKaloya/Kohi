#if DEBUG
import CoreGraphics
import SwiftUI

/// Three things to scan when there is nothing on the desk: a bag for the
/// collection, the card a café puts by the cup, and a café's menu. Drawn in
/// code and then laid on the same surface as the archive sample, so the
/// review, the read and both flows run exactly as they do on paper.
///
/// Debug builds only: a TestFlight or App Store build has no demo.
enum DemoScan: String, CaseIterable, Identifiable {
    case bag
    case card
    case menu

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bag: "Bag"
        case .card: "Café card"
        case .menu: "Menu"
        }
    }

    static let size = CGSize(width: 400, height: 540)

    /// `KOHI_DEMO=bag|card|menu` makes the simulator shutter file that demo.
    static var requested: DemoScan? {
        ProcessInfo.processInfo.environment["KOHI_DEMO"].flatMap(DemoScan.init(rawValue:))
    }

    /// The flat artwork, before it is laid on the surface.
    func image(scale: CGFloat = 3) -> CGImage? {
        let renderer = ImageRenderer(content: artwork.frame(width: Self.size.width, height: Self.size.height))
        renderer.scale = scale
        return renderer.cgImage
    }

    /// The artwork as though it had just been photographed.
    func capture() -> CapturedCard? {
        guard let image = image() else { return nil }
        return SampleArchive.sampleCapture(image: image)
    }

    @ViewBuilder
    private var artwork: some View {
        switch self {
        case .bag: DemoBag()
        case .card: DemoCafeCard()
        case .menu: DemoMenu()
        }
    }
}

private struct DemoBag: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("FÈVE")
                .font(.system(size: 20, weight: .heavy))
                .tracking(4)
            Spacer().frame(height: 18)
            Text("Ethiopia Chelchele")
                .font(.system(size: 34, weight: .bold, design: .serif))
            Spacer().frame(height: 10)
            line("Origin", "Ethiopia")
            line("Region", "Gedeo")
            line("Process", "Washed")
            line("Variety", "Heirloom")
            line("Altitude", "2000 m")
            line("Notes", "Jasmine, peach, bergamot")
            Spacer()
            Text("250 g · Whole bean")
                .font(.system(size: 15, weight: .medium))
        }
        .foregroundStyle(Color(red: 0.16, green: 0.12, blue: 0.09))
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(red: 0.80, green: 0.68, blue: 0.52))
    }

    private func line(_ label: String, _ value: String) -> some View {
        Text("\(label): \(value)")
            .font(.system(size: 17, weight: .regular))
    }
}

private struct DemoCafeCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("COFFEE OF THE DAY")
                .font(.system(size: 14, weight: .semibold))
                .tracking(3)
            Spacer().frame(height: 14)
            Text("Kenya Tekangu")
                .font(.system(size: 36, weight: .bold, design: .serif))
            Text("Belleville")
                .font(.system(size: 20, weight: .medium))
            Spacer().frame(height: 12)
            Text("Notes: Floral, red currant, vanilla")
            Text("Region: Nyeri, Kenya")
            Text("Process: Washed")
            Text("Altitude: 1800 m")
            Spacer()
            Text("V60 — 5,50 €")
                .font(.system(size: 20, weight: .semibold))
        }
        .font(.system(size: 17))
        .foregroundStyle(.black)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(white: 0.97))
    }
}

private struct DemoMenu: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FILTRE")
                .font(.system(size: 24, weight: .heavy))
                .tracking(5)
            Spacer().frame(height: 16)
            entry("Ethiopia Guji 5,50 €", roaster: "Fève", process: "Washed")
            entry("Kenya Kiambu AA 6 €", roaster: "Belleville", process: "Washed")
            entry("Colombia El Paraiso 7 €", roaster: "Hexagone", process: "Natural")
            Spacer()
        }
        .foregroundStyle(Color(white: 0.95))
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(red: 0.13, green: 0.14, blue: 0.13))
    }

    private func entry(_ line: String, roaster: String, process: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(line)
                .font(.system(size: 22, weight: .semibold))
            Text(roaster)
                .font(.system(size: 16))
            Text(process)
                .font(.system(size: 16))
                .opacity(0.75)
        }
        .padding(.bottom, 18)
    }
}
#endif
