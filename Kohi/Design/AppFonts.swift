import CoreText
import Foundation
import os

/// Registers bundled display faces before any view asks for them.
enum AppFonts {
    static let angustaDemiBold = "AngustaTest-DemiBold"

    static func register() {
        if isAvailable { return }

        guard let url = fontURL() else {
            Log.app.error("AngustaTest-DemiBold.otf missing from app bundle")
            return
        }

        var error: Unmanaged<CFError>?
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)

        if !isAvailable {
            let message = error?.takeRetainedValue().localizedDescription ?? "unknown"
            Log.app.error("Angusta not available after registration: \(message, privacy: .public)")
        }
    }

    private static var isAvailable: Bool {
        let probe = CTFontCreateWithName(angustaDemiBold as CFString, 22, nil)
        return (CTFontCopyPostScriptName(probe) as String) == angustaDemiBold
    }

    private static func fontURL() -> URL? {
        if let url = Bundle.main.url(forResource: "AngustaTest-DemiBold", withExtension: "otf") {
            return url
        }
        guard let root = Bundle.main.resourceURL else { return nil }
        return FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .first { $0.lastPathComponent == "AngustaTest-DemiBold.otf" }
    }
}
