import SwiftUI

struct ProfileView: View {
    @Environment(WardrobeStore.self) private var wardrobe
    @State private var availability = AIAvailabilityChecker.current()

    var body: some View {
        NavigationStack {
            List {
                Section("Your wardrobe") {
                    LabeledContent("Items", value: "\(wardrobe.items.count)")
                    ForEach([ClothingCategory.tops, .bottoms, .shoes], id: \.self) { category in
                        LabeledContent(category.displayName, value: "\(wardrobe.items.filter { $0.category == category }.count)")
                    }
                }

                Section {
                    Label(availability.message, systemImage: availability.isAvailable ? "sparkles" : "exclamationmark.triangle")
                } header: {
                    Text("On-device AI")
                } footer: {
                    Text("AI suggests details when you add an item, which you always confirm, and writes short outfit explanations. The app itself picks every outfit, so matching works without AI.")
                }

                Section("Privacy") {
                    Label("Photos and wardrobe details stay on this iPhone.", systemImage: "lock")
                    Label("No account, no cloud, no third-party AI services.", systemImage: "icloud.slash")
                }
            }
            .navigationTitle("Profile")
            .onAppear { availability = AIAvailabilityChecker.current() }
        }
    }
}
