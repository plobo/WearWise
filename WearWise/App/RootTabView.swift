import SwiftUI

struct RootTabView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var selectedTab = RootTabView.initialTab

    static var initialTab: Int {
        #if DEBUG
        if DebugSampleWardrobe.shouldOpenFirstMatch { return 1 }
        #endif
        return 0
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Wardrobe", systemImage: "hanger", value: 0) {
                WardrobeView()
            }
            Tab("Match", systemImage: "sparkles.rectangle.stack", value: 1) {
                MatchView()
            }
            Tab("Profile", systemImage: "person.crop.circle", value: 2) {
                ProfileView()
            }
        }
        .safeAreaInset(edge: .top) {
            if let warning = dependencies.storageWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(.orange.opacity(0.2))
            }
        }
    }
}
