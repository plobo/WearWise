import Foundation
import SwiftData

// Every released schema version stays defined here so older stores can be migrated step by step.
// Each version declares its own model classes, as SwiftData requires.

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

/// V5 adds an accessory type to items and optional accessories to outfits.
enum WardrobeSchemaV5: VersionedSchema {
    static let versionIdentifier = Schema.Version(5, 0, 0)
    static var models: [any PersistentModel.Type] { [ClothingItemRecord.self, OutfitRecord.self] }

    @Model
    final class ClothingItemRecord {
        @Attribute(.unique) var id: UUID
        var name: String
        var categoryRaw: String
        var accessoryKindRaw: String?
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
            accessoryKindRaw = item.accessoryKind?.rawValue
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
        var accessoryIDs: [UUID] = []
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
            accessoryIDs = outfit.accessoryIDs
            isSaved = outfit.isSaved
            isHidden = outfit.isHidden
            wornDates = outfit.wornDates
            dateCreated = outfit.dateCreated
        }
    }
}

/// The current record types.
typealias ClothingItemRecord = WardrobeSchemaV5.ClothingItemRecord
typealias OutfitRecord = WardrobeSchemaV5.OutfitRecord
typealias CurrentWardrobeSchema = WardrobeSchemaV5

enum WardrobeMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [WardrobeSchemaV1.self, WardrobeSchemaV2.self, WardrobeSchemaV3.self, WardrobeSchemaV4.self, WardrobeSchemaV5.self]
    }
    static var stages: [MigrationStage] { [v1ToV2, v2ToV3, v3ToV4, v4ToV5] }

    /// Adding an optional property needs no data transformation.
    static let v1ToV2 = MigrationStage.lightweight(fromVersion: WardrobeSchemaV1.self, toVersion: WardrobeSchemaV2.self)
    /// Adding a new entity needs no data transformation.
    static let v2ToV3 = MigrationStage.lightweight(fromVersion: WardrobeSchemaV2.self, toVersion: WardrobeSchemaV3.self)
    /// Making pants optional and adding an optional layer needs no data transformation.
    static let v3ToV4 = MigrationStage.lightweight(fromVersion: WardrobeSchemaV3.self, toVersion: WardrobeSchemaV4.self)
    /// New optional / defaulted properties need no data transformation.
    static let v4ToV5 = MigrationStage.lightweight(fromVersion: WardrobeSchemaV4.self, toVersion: WardrobeSchemaV5.self)
}
