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
                .tint(Theme.accent)
        }
    }
}
