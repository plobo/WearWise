import SwiftUI

/// Pick a top from your closet (or add a new one) to see matching pants and shoes.
struct MatchView: View {
    @Environment(WardrobeStore.self) private var wardrobe
    @State private var path: [UUID] = []
    @State private var showingAdd = false

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle("Match")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showingAdd = true
                        } label: {
                            Label("Add a new top", systemImage: "camera")
                        }
                    }
                }
                .navigationDestination(for: UUID.self) { id in
                    MatchResultsView(topID: id)
                }
                .sheet(isPresented: $showingAdd) {
                    AddClothingView { item in
                        if item.category == .tops { path = [item.id] }
                    }
                }
        }
        #if DEBUG
        .onAppear {
            if DebugSampleWardrobe.shouldOpenFirstMatch, path.isEmpty,
               let top = wardrobe.items.first(where: { $0.category == .tops && $0.formality == .smartCasual }) {
                path = [top.id]
            }
        }
        #endif
    }

    @ViewBuilder
    private var content: some View {
        let tops = wardrobe.items.filter { $0.category == .tops }
        if tops.isEmpty {
            ContentUnavailableView {
                Label("No tops yet", systemImage: "tshirt")
            } description: {
                Text("Add a shirt or other top, plus some pants and shoes, and WearWise will suggest what goes together.")
            } actions: {
                Button("Add a top") { showingAdd = true }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            ScrollView {
                Text("Which top are you wearing?")
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                Text("Suggestions only use pants and shoes you own.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(tops) { top in
                        NavigationLink(value: top.id) {
                            ClothingCard(item: top)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

/// Ready-made outfits for one top, best first.
struct MatchResultsView: View {
    let topID: UUID

    @Environment(WardrobeStore.self) private var wardrobe
    @Environment(OutfitStore.self) private var outfits
    @State private var lastHidden: OutfitKey?
    @State private var errorMessage: String?

    var body: some View {
        if let top = wardrobe.item(id: topID) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header(top)
                    results(for: top)
                }
                .padding()
                .animation(.default, value: outfits.outfits)
            }
            .navigationTitle("Match this top")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) { undoBanner }
            .alert("Something went wrong", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        } else {
            ContentUnavailableView("Item not found", systemImage: "questionmark.square.dashed")
        }
    }

    private func header(_ top: ClothingItem) -> some View {
        HStack(spacing: 12) {
            ItemThumbnail(item: top, padding: 6)
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                Text(top.name).font(.headline)
                HStack(spacing: 4) {
                    ColorSwatch(color: top.primaryColor)
                    Text("\(top.primaryColor.displayName) · \(top.formality.displayName)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func results(for top: ClothingItem) -> some View {
        switch OutfitMatcher.match(top: top, wardrobe: wardrobe.items, context: outfits.matchContext()) {
        case .suggestions(let suggestions):
            Text("Best outfits from your closet")
                .font(.title3.weight(.semibold))
            ForEach(suggestions) { suggestion in
                OutfitCard(
                    suggestion: suggestion,
                    isSaved: outfits.isSaved(suggestion.key),
                    isWornToday: outfits.isWornToday(suggestion.key),
                    onSave: { perform { try outfits.toggleSaved(suggestion.key) } },
                    onWore: { perform { try outfits.toggleWornToday(suggestion.key) } },
                    onHide: {
                        perform {
                            try outfits.hide(suggestion.key)
                            lastHidden = suggestion.key
                        }
                    }
                )
            }
        case .missingPieces(let needsBottoms, let needsShoes):
            let missing = [needsBottoms ? "pants" : nil, needsShoes ? "shoes" : nil].compactMap { $0 }.joined(separator: " and ")
            ContentUnavailableView(
                "Add some \(missing)",
                systemImage: "hanger",
                description: Text("WearWise only suggests clothes you own. Add \(missing) to your wardrobe to see outfits for this top.")
            )
        case .noGoodMatches:
            ContentUnavailableView(
                "No strong matches",
                systemImage: "circle.slash",
                description: Text("None of your pants and shoes go well with this top on colour or how casual or formal they are.")
            )
        case .allHidden:
            ContentUnavailableView(
                "All matches hidden",
                systemImage: "eye.slash",
                description: Text("You've hidden every good match for this top. Restore them from Hidden suggestions in the Outfits tab.")
            )
        }
    }

    @ViewBuilder
    private var undoBanner: some View {
        if let key = lastHidden {
            HStack {
                Text("Outfit hidden. It won't be suggested again.")
                    .font(.subheadline)
                Spacer()
                Button("Undo") {
                    perform { try outfits.unhide(key) }
                    lastHidden = nil
                }
                .fontWeight(.semibold)
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
            .padding(.horizontal)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: key) {
                try? await Task.sleep(for: .seconds(5))
                if lastHidden == key { withAnimation { lastHidden = nil } }
            }
        }
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { errorMessage = error.localizedDescription }
    }
}

private struct OutfitCard: View {
    let suggestion: OutfitSuggestion
    let isSaved: Bool
    let isWornToday: Bool
    let onSave: () -> Void
    let onWore: () -> Void
    let onHide: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                OutfitPiece(item: suggestion.bottom)
                Image(systemName: "plus").foregroundStyle(.secondary).accessibilityHidden(true)
                OutfitPiece(item: suggestion.shoes)
            }
            HStack {
                Text(suggestion.title).font(.headline)
                Spacer()
                Text(suggestion.rating)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.accent.opacity(0.15), in: Capsule())
            }
            Text(suggestion.reasons.joined(separator: ". ") + ".")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                actionButton(isSaved ? "Saved" : "Save", systemImage: isSaved ? "bookmark.fill" : "bookmark", active: isSaved, action: onSave)
                actionButton(isWornToday ? "Worn today" : "Wore today", systemImage: isWornToday ? "checkmark.circle.fill" : "checkmark.circle", active: isWornToday, action: onWore)
                Spacer()
                Button(action: onHide) {
                    Label("Not for me", systemImage: "hand.thumbsdown")
                        .labelStyle(.iconOnly)
                        .padding(8)
                }
                .buttonStyle(.bordered)
                .clipShape(Circle())
                .accessibilityLabel("Not for me")
                .accessibilityHint("Hides this outfit from suggestions")
            }
        }
        .padding(12)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
        .accessibilityElement(children: .contain)
    }

    private func actionButton(_ title: String, systemImage: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.medium))
        }
        .buttonStyle(.bordered)
        .tint(active ? Theme.accent : .secondary)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

/// A tappable thumbnail that opens the item.
struct OutfitPiece: View {
    let item: ClothingItem
    var maxWidth: CGFloat = 120

    var body: some View {
        NavigationLink {
            ClothingDetailView(itemID: item.id)
        } label: {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: maxWidth)
                .overlay { ItemThumbnail(item: item) }
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .accessibilityLabel(item.name)
    }
}
