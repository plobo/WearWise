import SwiftUI

struct ProfileView: View {
    @Environment(WardrobeStore.self) private var wardrobe
    @Environment(PreferencesStore.self) private var preferences
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
                    NavigationLink {
                        ColorPreferenceList(mode: .love)
                    } label: {
                        LabeledContent("Colours I love", value: summary(preferences.preferences.favoriteColors))
                    }
                    NavigationLink {
                        ColorPreferenceList(mode: .avoid)
                    } label: {
                        LabeledContent("Colours I avoid", value: summary(preferences.preferences.avoidedColors))
                    }
                    Picker("Usual style", selection: Binding(
                        get: { preferences.preferences.usualFormality },
                        set: { preferences.setUsualFormality($0) }
                    )) {
                        Text("No preference").tag(Formality?.none)
                        ForEach(Formality.allCases, id: \.self) { Text($0.displayName).tag(Optional($0)) }
                    }
                } header: {
                    Text("Style preferences")
                } footer: {
                    Text("These gently reorder suggestions. They never change which outfits qualify, and never suggest clothes you don't own.")
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

    private func summary(_ colors: Set<ClothingColor>) -> String {
        guard !colors.isEmpty else { return "None" }
        let names = ClothingColor.allCases.filter(colors.contains).map(\.displayName)
        return names.count > 2 ? "\(names.prefix(2).joined(separator: ", ")) +\(names.count - 2)" : names.joined(separator: ", ")
    }
}

private struct ColorPreferenceList: View {
    enum Mode { case love, avoid }
    let mode: Mode

    @Environment(PreferencesStore.self) private var preferences

    var body: some View {
        List {
            Section {
                ForEach(ClothingColor.allCases, id: \.self) { color in
                    let selected = isSelected(color)
                    let inOtherList = mode == .love
                        ? preferences.preferences.avoidedColors.contains(color)
                        : preferences.preferences.favoriteColors.contains(color)
                    Button {
                        mode == .love ? preferences.toggleFavorite(color) : preferences.toggleAvoided(color)
                    } label: {
                        HStack(spacing: 12) {
                            ColorSwatch(color: color, size: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(color.displayName).foregroundStyle(.primary)
                                if inOtherList {
                                    Text(mode == .love ? "Currently avoided" : "Currently a favourite")
                                        .font(.caption)
                                        .foregroundStyle(Theme.secondaryText)
                                }
                            }
                            Spacer()
                            if selected {
                                Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            } footer: {
                Text(mode == .love
                     ? "Pants and shoes in these colours move up in suggestions."
                     : "Pants and shoes in these colours move down, and jackets or accessories in them aren't suggested.")
            }
        }
        .navigationTitle(mode == .love ? "Colours I love" : "Colours I avoid")
    }

    private func isSelected(_ color: ClothingColor) -> Bool {
        mode == .love
            ? preferences.preferences.favoriteColors.contains(color)
            : preferences.preferences.avoidedColors.contains(color)
    }
}
