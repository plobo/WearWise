import SwiftUI

/// Saved outfits, what you've worn recently, and hidden suggestions.
struct OutfitsView: View {
    @Environment(WardrobeStore.self) private var wardrobe
    @Environment(OutfitStore.self) private var outfits
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            let saved = outfits.saved.compactMap { ResolvedOutfit($0, wardrobe: wardrobe.items) }
            let worn = outfits.recentlyWorn.compactMap { ResolvedOutfit($0, wardrobe: wardrobe.items) }
            let hiddenCount = outfits.hidden.count

            Group {
                if saved.isEmpty, worn.isEmpty, hiddenCount == 0 {
                    ContentUnavailableView {
                        Label("No outfits yet", systemImage: "bookmark")
                    } description: {
                        Text("In Match, save the outfits you like and tap Wore today when you wear one. They'll show up here.")
                    }
                } else {
                    List {
                        if !saved.isEmpty {
                            Section("Saved") {
                                ForEach(saved) { row($0) }
                            }
                        }
                        if !worn.isEmpty {
                            Section("Recently worn") {
                                ForEach(worn) { row($0) }
                            }
                        }
                        if hiddenCount > 0 {
                            Section {
                                NavigationLink {
                                    HiddenOutfitsView()
                                } label: {
                                    LabeledContent("Hidden suggestions", value: "\(hiddenCount)")
                                }
                            } footer: {
                                Text("Outfits you marked \"Not for me\" aren't suggested again.")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Outfits")
            .alert("Something went wrong", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func row(_ resolved: ResolvedOutfit) -> some View {
        let key = resolved.outfit.key
        let wornToday = outfits.isWornToday(key)
        return OutfitRow(resolved: resolved, wornToday: wornToday)
            .swipeActions(edge: .leading) {
                Button {
                    perform { try outfits.toggleWornToday(key) }
                } label: {
                    Label(wornToday ? "Not worn today" : "Wore today", systemImage: "checkmark.circle")
                }
                .tint(Theme.accent)
            }
            .swipeActions(edge: .trailing) {
                if resolved.outfit.isSaved {
                    Button {
                        perform { try outfits.toggleSaved(key) }
                    } label: {
                        Label("Unsave", systemImage: "bookmark.slash")
                    }
                } else {
                    Button(role: .destructive) {
                        perform { try outfits.remove(resolved.outfit) }
                    } label: {
                        Label("Forget", systemImage: "trash")
                    }
                }
            }
            .contextMenu {
                Button {
                    perform { try outfits.toggleWornToday(key) }
                } label: {
                    Label(wornToday ? "Not worn today" : "Wore today", systemImage: "checkmark.circle")
                }
                Button {
                    perform { try outfits.toggleSaved(key) }
                } label: {
                    Label(resolved.outfit.isSaved ? "Unsave" : "Save", systemImage: "bookmark")
                }
            }
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { errorMessage = error.localizedDescription }
    }
}

private struct OutfitRow: View {
    let resolved: ResolvedOutfit
    let wornToday: Bool

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                ForEach([resolved.top, resolved.bottom, resolved.shoes]) { item in
                    ItemThumbnail(item: item, padding: 4)
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(resolved.bottom.name) + \(resolved.shoes.name)")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                Text("with \(resolved.top.name)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(wearSummary)
                    .font(.caption)
                    .foregroundStyle(wornToday ? Theme.accent : .secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(resolved.top.name), \(resolved.bottom.name) and \(resolved.shoes.name). \(wearSummary)")
    }

    private var wearSummary: String {
        let outfit = resolved.outfit
        guard let last = outfit.lastWorn else { return "Not worn yet" }
        let times = outfit.timesWorn == 1 ? "Worn once" : "Worn \(outfit.timesWorn) times"
        if wornToday { return "\(times) · today" }
        return "\(times) · last \(last.formatted(.relative(presentation: .named)))"
    }
}

private struct HiddenOutfitsView: View {
    @Environment(WardrobeStore.self) private var wardrobe
    @Environment(OutfitStore.self) private var outfits

    var body: some View {
        let hidden = outfits.hidden.compactMap { ResolvedOutfit($0, wardrobe: wardrobe.items) }
        List {
            ForEach(hidden) { resolved in
                HStack {
                    OutfitRow(resolved: resolved, wornToday: false)
                    Spacer()
                    Button("Restore") {
                        try? outfits.unhide(resolved.outfit.key)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .overlay {
            if hidden.isEmpty {
                ContentUnavailableView("Nothing hidden", systemImage: "eye")
            }
        }
        .navigationTitle("Hidden suggestions")
    }
}
