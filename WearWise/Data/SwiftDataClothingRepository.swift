import Foundation
import SwiftData

// MARK: - Schema

enum WardrobeSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [ClothingItemRecord.self] }

    @Model
    final class ClothingItemRecord {
        @Attribute(.unique) var id: UUID
        var name: String
        var categoryRaw: String
        var primaryColorRaw: String
        var secondaryColorsRaw: [String]
        var patternRaw: String
        var formalityRaw: String
        var isFavorite: Bool
        var imagePath: String
        var thumbnailPath: String
        var dateAdded: Date
        var dateModified: Date
        var aiStatusRaw: String

        init(item: ClothingItem) {
            id = item.id
            name = item.name
            categoryRaw = item.category.rawValue
            primaryColorRaw = item.primaryColor.rawValue
            secondaryColorsRaw = item.secondaryColors.map(\.rawValue)
            patternRaw = item.pattern.rawValue
            formalityRaw = item.formality.rawValue
            isFavorite = item.isFavorite
            imagePath = item.imagePath
            thumbnailPath = item.thumbnailPath
            dateAdded = item.dateAdded
            dateModified = item.dateModified
            aiStatusRaw = item.aiStatus.rawValue
        }
    }
}

/// V2 adds an optional background-removed image.
enum WardrobeSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] { [ClothingItemRecord.self] }

    @Model
    final class ClothingItemRecord {
        @Attribute(.unique) var id: UUID
        var name: String
        var categoryRaw: String
        var primaryColorRaw: String
        var secondaryColorsRaw: [String]
        var patternRaw: String
        var formalityRaw: String
        var isFavorite: Bool
        var imagePath: String
        var thumbnailPath: String
        var cutoutPath: String?
        var dateAdded: Date
        var dateModified: Date
        var aiStatusRaw: String

        init(item: ClothingItem) {
            id = item.id
            name = item.name
            categoryRaw = item.category.rawValue
            primaryColorRaw = item.primaryColor.rawValue
            secondaryColorsRaw = item.secondaryColors.map(\.rawValue)
            patternRaw = item.pattern.rawValue
            formalityRaw = item.formality.rawValue
            isFavorite = item.isFavorite
            imagePath = item.imagePath
            thumbnailPath = item.thumbnailPath
            cutoutPath = item.cutoutPath
            dateAdded = item.dateAdded
            dateModified = item.dateModified
            aiStatusRaw = item.aiStatus.rawValue
        }
    }
}

/// V3 adds saved, hidden and worn outfits. Clothing items are unchanged from V2.
enum WardrobeSchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)
    static var models: [any PersistentModel.Type] { [ClothingItemRecord.self, OutfitRecord.self] }

    @Model
    final class ClothingItemRecord {
        @Attribute(.unique) var id: UUID
        var name: String
        var categoryRaw: String
        var primaryColorRaw: String
        var secondaryColorsRaw: [String]
        var patternRaw: String
        var formalityRaw: String
        var isFavorite: Bool
        var imagePath: String
        var thumbnailPath: String
        var cutoutPath: String?
        var dateAdded: Date
        var dateModified: Date
        var aiStatusRaw: String

        init(item: ClothingItem) {
            id = item.id
            name = item.name
            categoryRaw = item.category.rawValue
            primaryColorRaw = item.primaryColor.rawValue
            secondaryColorsRaw = item.secondaryColors.map(\.rawValue)
            patternRaw = item.pattern.rawValue
            formalityRaw = item.formality.rawValue
            isFavorite = item.isFavorite
            imagePath = item.imagePath
            thumbnailPath = item.thumbnailPath
            cutoutPath = item.cutoutPath
            dateAdded = item.dateAdded
            dateModified = item.dateModified
            aiStatusRaw = item.aiStatus.rawValue
        }
    }

    @Model
    final class OutfitRecord {
        @Attribute(.unique) var id: UUID
        var topID: UUID
        var bottomID: UUID
        var shoesID: UUID
        var isSaved: Bool
        var isHidden: Bool
        var wornDates: [Date]
        var dateCreated: Date

        /// Only used to create version 3 data in migration tests; V3 can't represent dress outfits.
        init(outfit: Outfit) {
            id = outfit.id
            topID = outfit.key.topID
            bottomID = outfit.key.bottomID ?? UUID()
            shoesID = outfit.key.shoesID
            isSaved = outfit.isSaved
            isHidden = outfit.isHidden
            wornDates = outfit.wornDates
            dateCreated = outfit.dateCreated
        }
    }
}

/// V4 supports dress outfits (no pants) and an optional outer layer. Clothing items are unchanged.
enum WardrobeSchemaV4: VersionedSchema {
    static let versionIdentifier = Schema.Version(4, 0, 0)
    static var models: [any PersistentModel.Type] { [ClothingItemRecord.self, OutfitRecord.self] }

    @Model
    final class ClothingItemRecord {
        @Attribute(.unique) var id: UUID
        var name: String
        var categoryRaw: String
        var primaryColorRaw: String
        var secondaryColorsRaw: [String]
        var patternRaw: String
        var formalityRaw: String
        var isFavorite: Bool
        var imagePath: String
        var thumbnailPath: String
        var cutoutPath: String?
        var dateAdded: Date
        var dateModified: Date
        var aiStatusRaw: String

        init(item: ClothingItem) {
            id = item.id
            name = item.name
            categoryRaw = item.category.rawValue
            primaryColorRaw = item.primaryColor.rawValue
            secondaryColorsRaw = item.secondaryColors.map(\.rawValue)
            patternRaw = item.pattern.rawValue
            formalityRaw = item.formality.rawValue
            isFavorite = item.isFavorite
            imagePath = item.imagePath
            thumbnailPath = item.thumbnailPath
            cutoutPath = item.cutoutPath
            dateAdded = item.dateAdded
            dateModified = item.dateModified
            aiStatusRaw = item.aiStatus.rawValue
        }
    }

    @Model
    final class OutfitRecord {
        @Attribute(.unique) var id: UUID
        /// The starting piece: a top or a dress.
        var topID: UUID
        var bottomID: UUID?
        var shoesID: UUID
        var layerID: UUID?
        var isSaved: Bool
        var isHidden: Bool
        var wornDates: [Date]
        var dateCreated: Date

        init(outfit: Outfit) {
            id = outfit.id
            topID = outfit.key.topID
            bottomID = outfit.key.bottomID
            shoesID = outfit.key.shoesID
            layerID = outfit.layerID
            isSaved = outfit.isSaved
            isHidden = outfit.isHidden
            wornDates = outfit.wornDates
            dateCreated = outfit.dateCreated
        }
    }
}

/// The current record types. Older versions stay defined so stores can be migrated.
typealias ClothingItemRecord = WardrobeSchemaV4.ClothingItemRecord
typealias OutfitRecord = WardrobeSchemaV4.OutfitRecord
typealias CurrentWardrobeSchema = WardrobeSchemaV4

enum WardrobeMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [WardrobeSchemaV1.self, WardrobeSchemaV2.self, WardrobeSchemaV3.self, WardrobeSchemaV4.self]
    }
    static var stages: [MigrationStage] { [v1ToV2, v2ToV3, v3ToV4] }

    /// Making pants optional and adding an optional layer needs no data transformation.
    static let v3ToV4 = MigrationStage.lightweight(fromVersion: WardrobeSchemaV3.self, toVersion: WardrobeSchemaV4.self)

    /// Adding an optional property needs no data transformation.
    static let v1ToV2 = MigrationStage.lightweight(fromVersion: WardrobeSchemaV1.self, toVersion: WardrobeSchemaV2.self)
    /// Adding a new entity needs no data transformation.
    static let v2ToV3 = MigrationStage.lightweight(fromVersion: WardrobeSchemaV2.self, toVersion: WardrobeSchemaV3.self)
}

extension ClothingItemRecord {
    func apply(_ item: ClothingItem) {
        name = item.name
        categoryRaw = item.category.rawValue
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
        isSaved = outfit.isSaved
        isHidden = outfit.isHidden
        wornDates = outfit.wornDates
    }

    var domain: Outfit {
        Outfit(
            id: id,
            key: OutfitKey(topID: topID, bottomID: bottomID, shoesID: shoesID),
            layerID: layerID,
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
        try context.save()
    }

    private func record(id: UUID) throws -> OutfitRecord? {
        var descriptor = FetchDescriptor<OutfitRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
