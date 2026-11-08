import Foundation

enum WardrobeSort: String, CaseIterable, Sendable {
    case recent, name, category

    var displayName: String {
        switch self {
        case .recent: "Recently added"
        case .name: "Name"
        case .category: "Category"
        }
    }
}

/// Search, filter and sort rules for the wardrobe grid.
struct WardrobeQuery: Equatable, Sendable {
    var searchText = ""
    var category: ClothingCategory?
    var color: ClothingColor?
    var favoritesOnly = false
    var sort: WardrobeSort = .recent

    var isFiltering: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty || category != nil || color != nil || favoritesOnly
    }

    func apply(to items: [ClothingItem]) -> [ClothingItem] {
        let terms = searchText.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        let filtered = items.filter { item in
            if let category, item.category != category { return false }
            if let color, item.primaryColor != color, !item.secondaryColors.contains(color) { return false }
            if favoritesOnly, !item.isFavorite { return false }
            guard !terms.isEmpty else { return true }
            let haystack = Self.searchText(for: item)
            return terms.allSatisfy { haystack.contains($0) }
        }
        return filtered.sorted { a, b in
            switch sort {
            case .recent:
                return a.dateAdded > b.dateAdded
            case .name:
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            case .category:
                if a.category != b.category {
                    return ClothingCategory.allCases.firstIndex(of: a.category)! < ClothingCategory.allCases.firstIndex(of: b.category)!
                }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
        }
    }

    static func searchText(for item: ClothingItem) -> String {
        ([item.name, item.category.displayName, item.pattern.displayName, item.formality.displayName]
            + ([item.primaryColor] + item.secondaryColors).map(\.displayName))
            .joined(separator: " ")
            .lowercased()
    }
}
