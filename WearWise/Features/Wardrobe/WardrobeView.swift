import SwiftUI

struct WardrobeView: View {
    @Environment(WardrobeStore.self) private var wardrobe
    @State private var query = WardrobeQuery()
    @State private var showingAdd = false

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("My Wardrobe")
                .searchable(text: $query.searchText, prompt: "Search name, colour, category")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { sortAndFilterMenu }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showingAdd = true
                        } label: {
                            Label("Add clothing", systemImage: "plus")
                        }
                    }
                }
                .navigationDestination(for: UUID.self) { id in
                    ClothingDetailView(itemID: id)
                }
                .sheet(isPresented: $showingAdd) {
                    AddClothingView()
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if wardrobe.items.isEmpty {
            ContentUnavailableView {
                Label("Your wardrobe is empty", systemImage: "hanger")
            } description: {
                Text(wardrobe.loadError ?? "Add your tops, pants and shoes. WearWise uses them to suggest outfits from clothes you already own.")
            } actions: {
                Button("Add clothing") { showingAdd = true }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            let results = query.apply(to: wardrobe.items)
            ScrollView {
                categoryChips
                if results.isEmpty {
                    ContentUnavailableView.search(text: query.searchText)
                        .padding(.top, 40)
                } else {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(results) { item in
                            NavigationLink(value: item.id) {
                                ClothingCard(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    private var categoryChips: some View {
        let present = ClothingCategory.allCases.filter { category in wardrobe.items.contains { $0.category == category } }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", selected: query.category == nil) { query.category = nil }
                ForEach(present, id: \.self) { category in
                    chip(category.displayName, selected: query.category == category) {
                        query.category = query.category == category ? nil : category
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(selected ? Theme.accent : Theme.cardBackground, in: Capsule())
                .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var sortAndFilterMenu: some View {
        Menu {
            Picker("Sort by", selection: $query.sort) {
                ForEach(WardrobeSort.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            Picker("Colour", selection: $query.color) {
                Text("Any colour").tag(ClothingColor?.none)
                ForEach(ClothingColor.allCases, id: \.self) { Text($0.displayName).tag(Optional($0)) }
            }
            .pickerStyle(.menu)
            Toggle("Favourites only", isOn: $query.favoritesOnly)
        } label: {
            Label("Sort and filter", systemImage: query.color != nil || query.favoritesOnly
                  ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
    }
}
