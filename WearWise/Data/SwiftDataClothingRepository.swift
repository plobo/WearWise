import Foundation
import SwiftData

extension ClothingItemRecord {
    func apply(_ item: ClothingItem) {
        name = item.name
        categoryRaw = item.category.rawValue
        accessoryKindRaw = item.accessoryKind?.rawValue
        primaryColorRaw = item.primaryColor.rawValue
        secondaryColorsRaw = item.secondaryColors.map(\.rawValue)
        patternRaw = item.pattern.rawValue
        formalityRaw = item.formality.rawValue
        isFavorite = item.isFavorite
        imagePath = item.imagePath
        thumbnailPath = item.thumbnailPath
        cutoutPath = item.cutoutPath
        dateModified = item.dateModified
        aiStatusRaw = item.aiStatus.rawValue
    }

    var domain: ClothingItem {
        ClothingItem(
            id: id,
            name: name,
            category: ClothingCategory(rawValue: categoryRaw) ?? .other,
            accessoryKind: accessoryKindRaw.flatMap(AccessoryKind.init(rawValue:)),
            primaryColor: ClothingColor(rawValue: primaryColorRaw) ?? .grey,
            secondaryColors: secondaryColorsRaw.compactMap(ClothingColor.init(rawValue:)),
            pattern: ClothingPattern(rawValue: patternRaw) ?? .unknown,
            formality: Formality(rawValue: formalityRaw) ?? .casual,
            isFavorite: isFavorite,
            imagePath: imagePath,
            thumbnailPath: thumbnailPath,
            cutoutPath: cutoutPath,
            dateAdded: dateAdded,
            dateModified: dateModified,
            aiStatus: AIAnalysisStatus(rawValue: aiStatusRaw) ?? .manual
        )
    }
}

// MARK: - Container

enum ModelContainerFactory {
    static func make(storeURL: URL? = nil, inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: CurrentWardrobeSchema.self)
        let configuration: ModelConfiguration
        if let storeURL {
            configuration = ModelConfiguration(schema: schema, url: storeURL)
        } else {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        }
        return try ModelContainer(for: schema, migrationPlan: WardrobeMigrationPlan.self, configurations: configuration)
    }
}

// MARK: - Repository

@MainActor
final class SwiftDataClothingRepository: ClothingRepository {
    /// Retained on purpose: a ModelContext does not keep its container alive.
    private let container: ModelContainer
    private let context: ModelContext

    init(container: ModelContainer) {
        self.container = container
        context = container.mainContext
    }

    func allItems() throws -> [ClothingItem] {
        let descriptor = FetchDescriptor<ClothingItemRecord>(sortBy: [SortDescriptor(\.dateAdded, order: .reverse)])
        return try context.fetch(descriptor).map(\.domain)
    }

    func insert(_ item: ClothingItem) throws {
        context.insert(ClothingItemRecord(item: item))
        try context.save()
    }

    func update(_ item: ClothingItem) throws {
        guard let record = try record(id: item.id) else { throw RepositoryError.notFound }
        record.apply(item)
        try context.save()
    }

    func delete(id: UUID) throws {
        guard let record = try record(id: id) else { return }
        context.delete(record)
        try context.save()
    }

    private func record(id: UUID) throws -> ClothingItemRecord? {
        var descriptor = FetchDescriptor<ClothingItemRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}

// MARK: - Outfits

extension OutfitRecord {
    func apply(_ outfit: Outfit) {
        layerID = outfit.layerID
        accessoryIDs = outfit.accessoryIDs
        isSaved = outfit.isSaved
        isHidden = outfit.isHidden
        wornDates = outfit.wornDates
    }

    var domain: Outfit {
        Outfit(
            id: id,
            key: OutfitKey(topID: topID, bottomID: bottomID, shoesID: shoesID),
            layerID: layerID,
            accessoryIDs: accessoryIDs,
            isSaved: isSaved,
            isHidden: isHidden,
            wornDates: wornDates.sorted(),
            dateCreated: dateCreated
        )
    }
}

@MainActor
final class SwiftDataOutfitRepository: OutfitRepository {
    /// Retained on purpose: a ModelContext does not keep its container alive.
    private let container: ModelContainer
    private let context: ModelContext

    init(container: ModelContainer) {
        self.container = container
        context = container.mainContext
    }

    func allOutfits() throws -> [Outfit] {
        let descriptor = FetchDescriptor<OutfitRecord>(sortBy: [SortDescriptor(\.dateCreated, order: .reverse)])
        return try context.fetch(descriptor).map(\.domain)
    }

    func insert(_ outfit: Outfit) throws {
        context.insert(OutfitRecord(outfit: outfit))
        try context.save()
    }

    func update(_ outfit: Outfit) throws {
        guard let record = try record(id: outfit.id) else { throw RepositoryError.notFound }
        record.apply(outfit)
        try context.save()
    }

    func delete(id: UUID) throws {
        guard let record = try record(id: id) else { return }
        context.delete(record)
        try context.save()
    }

    func deleteOutfits(containing itemID: UUID) throws {
        let core = FetchDescriptor<OutfitRecord>(predicate: #Predicate {
            $0.topID == itemID || $0.bottomID == itemID || $0.shoesID == itemID
        })
        for record in try context.fetch(core) {
            context.delete(record)
        }
        // A deleted jacket only drops out as the optional layer.
        let layered = FetchDescriptor<OutfitRecord>(predicate: #Predicate { $0.layerID == itemID })
        for record in try context.fetch(layered) {
            record.layerID = nil
        }
        // Accessories are optional extras too. Array membership can't be expressed in a predicate here.
        for record in try context.fetch(FetchDescriptor<OutfitRecord>()) where record.accessoryIDs.contains(itemID) {
            record.accessoryIDs.removeAll { $0 == itemID }
        }
        try context.save()
    }

    private func record(id: UUID) throws -> OutfitRecord? {
        var descriptor = FetchDescriptor<OutfitRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
