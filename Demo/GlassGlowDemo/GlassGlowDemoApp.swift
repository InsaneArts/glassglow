import SwiftUI

@main
struct GlassGlowDemoApp: App {
    init() {
        AssetRenderer.runIfRequested()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
        .windowToolbarStyle(.unified)
    }
}
