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

    var body: some View {
        if let top = wardrobe.item(id: topID) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header(top)
                    results(for: top)
                }
                .padding()
            }
            .navigationTitle("Match this top")
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("Item not found", systemImage: "questionmark.square.dashed")
        }
    }

    private func header(_ top: ClothingItem) -> some View {
        HStack(spacing: 12) {
            StoredImage(path: top.thumbnailPath)
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
        switch OutfitMatcher.match(top: top, wardrobe: wardrobe.items) {
        case .suggestions(let suggestions):
            Text("Best outfits from your closet")
                .font(.title3.weight(.semibold))
            ForEach(suggestions) { suggestion in
                OutfitCard(suggestion: suggestion)
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
        }
    }
}

private struct OutfitCard: View {
    let suggestion: OutfitSuggestion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                piece(suggestion.bottom)
                Image(systemName: "plus").foregroundStyle(.secondary).accessibilityHidden(true)
                piece(suggestion.shoes)
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
        }
        .padding(12)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
        .accessibilityElement(children: .combine)
    }

    private func piece(_ item: ClothingItem) -> some View {
        NavigationLink {
            ClothingDetailView(itemID: item.id)
        } label: {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: 120)
                .overlay { StoredImage(path: item.thumbnailPath) }
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .accessibilityLabel(item.name)
    }
}
