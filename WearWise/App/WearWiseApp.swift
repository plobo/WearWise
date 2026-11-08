import SwiftUI

@main
struct WearWiseApp: App {
    @State private var dependencies = AppDependencies.live()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(dependencies)
                .environment(dependencies.wardrobe)
                .environment(dependencies.outfits)
                .environment(dependencies.explanations)
                .environment(dependencies.preferences)
                .tint(Theme.accent)
        }
    }
}
