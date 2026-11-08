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

typealias ClothingItemRecord = WardrobeSchemaV1.ClothingItemRecord

enum WardrobeMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [WardrobeSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
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
            dateAdded: dateAdded,
            dateModified: dateModified,
            aiStatus: AIAnalysisStatus(rawValue: aiStatusRaw) ?? .manual
        )
    }
}

// MARK: - Container

enum ModelContainerFactory {
    static func make(storeURL: URL? = nil, inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: WardrobeSchemaV1.self)
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
