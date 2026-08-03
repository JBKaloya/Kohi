import SwiftUI

@main
struct KohiApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.light)
                .task { Haptics.prepare() }
        }
    }
}
