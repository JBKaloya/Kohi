import SwiftUI

@main
struct KohiApp: App {
    init() {
        AppFonts.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.light)
                .task { Haptics.prepare() }
        }
    }
}
