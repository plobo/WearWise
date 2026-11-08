import Foundation

enum RepositoryError: LocalizedError, Equatable {
    case notFound

    var errorDescription: String? { "That item no longer exists." }
}

/// Persistence boundary for wardrobe items. Image bytes are not stored here, only paths.
@MainActor
protocol ClothingRepository: AnyObject {
    func allItems() throws -> [ClothingItem]
    func insert(_ item: ClothingItem) throws
    func update(_ item: ClothingItem) throws
    func delete(id: UUID) throws
}
