import Foundation
import Observation

/// Shared, observable wardrobe state. Coordinates the repository and local image files.
@MainActor
@Observable
final class WardrobeStore {
    private(set) var items: [ClothingItem] = []
    private(set) var loadError: String?

    let imageStore: LocalImageStore
    private let repository: any ClothingRepository
    private let now: @MainActor () -> Date

    init(repository: any ClothingRepository, imageStore: LocalImageStore, now: @escaping @MainActor () -> Date = { .now }) {
        self.repository = repository
        self.imageStore = imageStore
        self.now = now
        reload()
    }

    func reload() {
        do {
            items = try repository.allItems()
            loadError = nil
        } catch {
            loadError = "Your wardrobe couldn't be loaded."
        }
    }

    func item(id: UUID) -> ClothingItem? {
        items.first { $0.id == id }
    }

    /// Saves photo files and a new record. Rolls back the files if the record can't be saved.
    @discardableResult
    func add(
        _ draft: ClothingDraft,
        photo: ImageProcessor.Prepared,
        status: AIAnalysisStatus
    ) throws -> ClothingItem {
        guard draft.isComplete, let category = draft.category, let primary = draft.primaryColor, let formality = draft.formality else {
            throw WardrobeError.incomplete(draft.missingFields)
        }
        let id = UUID()
        let imagePath = try imageStore.save(photo.jpegData, fileName: "\(id.uuidString).jpg")
        do {
            let thumbnailPath = try imageStore.save(photo.thumbnailData, fileName: "\(id.uuidString)_thumb.jpg")
            let timestamp = now()
            let item = ClothingItem(
                id: id,
                name: draft.trimmedName,
                category: category,
                primaryColor: primary,
                secondaryColors: draft.normalizedSecondaryColors,
                pattern: draft.pattern,
                formality: formality,
                isFavorite: false,
                imagePath: imagePath,
                thumbnailPath: thumbnailPath,
                dateAdded: timestamp,
                dateModified: timestamp,
                aiStatus: status
            )
            try repository.insert(item)
            items.insert(item, at: 0)
            return item
        } catch {
            try? imageStore.delete("\(id.uuidString).jpg")
            try? imageStore.delete("\(id.uuidString)_thumb.jpg")
            throw error
        }
    }

    /// Applies edited attributes to an existing item.
    @discardableResult
    func update(_ item: ClothingItem, with draft: ClothingDraft) throws -> ClothingItem {
        guard draft.isComplete, let category = draft.category, let primary = draft.primaryColor, let formality = draft.formality else {
            throw WardrobeError.incomplete(draft.missingFields)
        }
        var updated = item
        updated.name = draft.trimmedName
        updated.category = category
        updated.primaryColor = primary
        updated.secondaryColors = draft.normalizedSecondaryColors
        updated.pattern = draft.pattern
        updated.formality = formality
        if draft != ClothingDraft(item: item) {
            updated.dateModified = now()
            if item.aiStatus == .suggestedAccepted { updated.aiStatus = .suggestedEdited }
        }
        try save(updated)
        return updated
    }

    func toggleFavorite(_ item: ClothingItem) throws {
        var updated = item
        updated.isFavorite.toggle()
        try save(updated)
    }

    /// Removes the record first, then its photo files.
    func delete(_ item: ClothingItem) throws {
        try repository.delete(id: item.id)
        items.removeAll { $0.id == item.id }
        try? imageStore.delete(item.imagePath)
        try? imageStore.delete(item.thumbnailPath)
    }

    private func save(_ item: ClothingItem) throws {
        try repository.update(item)
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        }
    }
}

enum WardrobeError: LocalizedError, Equatable {
    case incomplete([String])

    var errorDescription: String? {
        switch self {
        case .incomplete(let fields):
            "Please fill in: \(fields.joined(separator: ", "))."
        }
    }
}
