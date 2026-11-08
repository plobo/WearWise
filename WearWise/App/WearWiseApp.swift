import SwiftUI

@main
struct WearWiseApp: App {
    @State private var dependencies = AppDependencies.live()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(dependencies)
                .environment(dependencies.wardrobe)
                .tint(Theme.accent)
        }
    }
}
