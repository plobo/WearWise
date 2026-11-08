import Foundation
import Observation

/// Shared, observable wardrobe state. Coordinates the repository and local image files.
@MainActor
@Observable
final class WardrobeStore {
    private(set) var items: [ClothingItem] = []
    private(set) var loadError: String?

    let imageStore: LocalImageStore
    /// Called after an item is deleted, e.g. to remove outfits that used it.
    @ObservationIgnored var onItemDeleted: (@MainActor (UUID) throws -> Void)?
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
    /// When a cut-out is given, it is stored too and used for the thumbnail. The original photo is always kept.
    @discardableResult
    func add(
        _ draft: ClothingDraft,
        photo: ImageProcessor.Prepared,
        cutout: ForegroundSegmenter.Cutout? = nil,
        status: AIAnalysisStatus
    ) throws -> ClothingItem {
        guard draft.isComplete, let category = draft.category, let primary = draft.primaryColor, let formality = draft.formality else {
            throw WardrobeError.incomplete(draft.missingFields)
        }
        let id = UUID()
        let files = Self.fileNames(for: id, hasCutout: cutout != nil)
        let imagePath = try imageStore.save(photo.jpegData, fileName: files.image)
        do {
            let thumbnailPath = try imageStore.save(cutout?.thumbnailPNGData ?? photo.thumbnailData, fileName: files.thumbnail)
            let cutoutPath = try cutout.map { try imageStore.save($0.pngData, fileName: files.cutout) }
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
                cutoutPath: cutoutPath,
                dateAdded: timestamp,
                dateModified: timestamp,
                aiStatus: status
            )
            try repository.insert(item)
            items.insert(item, at: 0)
            return item
        } catch {
            for file in [files.image, files.thumbnail, files.cutout] { try? imageStore.delete(file) }
            throw error
        }
    }

    private static func fileNames(for id: UUID, hasCutout: Bool) -> (image: String, thumbnail: String, cutout: String) {
        let base = id.uuidString
        // Cut-out thumbnails keep transparency, so they're PNG.
        return ("\(base).jpg", hasCutout ? "\(base)_thumb.png" : "\(base)_thumb.jpg", "\(base)_cutout.png")
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
        try? onItemDeleted?(item.id)
        for path in [item.imagePath, item.thumbnailPath, item.cutoutPath].compactMap({ $0 }) {
            try? imageStore.delete(path)
        }
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
