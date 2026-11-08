import Foundation

/// The user's stated taste. Only nudges the order of suggestions; never changes which clothes qualify.
struct StylePreferences: Codable, Equatable, Sendable {
    var favoriteColors: Set<ClothingColor> = []
    var avoidedColors: Set<ClothingColor> = []
    var usualFormality: Formality?

    static let none = StylePreferences()

    var isEmpty: Bool { favoriteColors.isEmpty && avoidedColors.isEmpty && usualFormality == nil }

    /// Loving a colour removes it from the avoided set, and vice versa.
    mutating func toggleFavorite(_ color: ClothingColor) {
        if favoriteColors.remove(color) == nil {
            favoriteColors.insert(color)
            avoidedColors.remove(color)
        }
    }

    mutating func toggleAvoided(_ color: ClothingColor) {
        if avoidedColors.remove(color) == nil {
            avoidedColors.insert(color)
            favoriteColors.remove(color)
        }
    }
}
