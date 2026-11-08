import SwiftUI

struct RootTabView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var selectedTab = RootTabView.initialTab

    static var initialTab: Int {
        #if DEBUG
        if DebugSampleWardrobe.shouldOpenFirstMatch { return 1 }
        if DebugSampleWardrobe.shouldOpenOutfits { return 2 }
        if DebugSampleWardrobe.shouldOpenInsights { return 3 }
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
            Tab("Outfits", systemImage: "bookmark", value: 2) {
                OutfitsView()
            }
            Tab("Insights", systemImage: "chart.bar", value: 3) {
                InsightsView()
            }
            Tab("Profile", systemImage: "person.crop.circle", value: 4) {
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
