import CoreGraphics
import Foundation
import SwiftData
import Testing
import UIKit
@testable import WearWise

// MARK: - Helpers

func makeItem(
    _ name: String,
    _ category: ClothingCategory,
    _ color: ClothingColor,
    _ formality: Formality,
    secondary: [ClothingColor] = [],
    favorite: Bool = false,
    added: Date = .now
) -> ClothingItem {
    let id = UUID()
    return ClothingItem(
        id: id, name: name, category: category, primaryColor: color, secondaryColors: secondary,
        pattern: .solid, formality: formality, isFavorite: favorite,
        imagePath: "\(id).jpg", thumbnailPath: "\(id)_thumb.jpg",
        dateAdded: added, dateModified: added, aiStatus: .manual
    )
}

func completeDraft(_ name: String = "Navy chinos") -> ClothingDraft {
    var draft = ClothingDraft()
    draft.name = name
    draft.category = .bottoms
    draft.primaryColor = .navy
    draft.formality = .smartCasual
    return draft
}

func samplePhoto() -> ImageProcessor.Prepared {
    let ctx = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 16,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    return ImageProcessor.Prepared(cgImage: ctx.makeImage()!, jpegData: Data([1, 2, 3]), thumbnailData: Data([4, 5]))
}

func tempDirectory() -> URL {
    FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
}

// MARK: - Repository

@MainActor
struct SwiftDataRepositoryTests {
    @Test func savesFetchesUpdatesAndDeletes() throws {
        let repo = SwiftDataClothingRepository(container: try ModelContainerFactory.make(inMemory: true))
        var item = makeItem("White tee", .tops, .white, .casual, secondary: [.navy])
        try repo.insert(item)
        #expect(try repo.allItems() == [item])

        item.name = "White crew tee"
        item.isFavorite = true
        try repo.update(item)
        #expect(try repo.allItems().first?.name == "White crew tee")
        #expect(try repo.allItems().first?.isFavorite == true)
        #expect(try repo.allItems().first?.secondaryColors == [.navy])

        try repo.delete(id: item.id)
        #expect(try repo.allItems().isEmpty)
    }

    @Test func updatingMissingItemThrows() throws {
        let repo = SwiftDataClothingRepository(container: try ModelContainerFactory.make(inMemory: true))
        #expect(throws: RepositoryError.notFound) {
            try repo.update(makeItem("Ghost", .tops, .white, .casual))
        }
    }

    @Test func persistsAcrossContainerRecreation() throws {
        let dir = tempDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "wardrobe.store")
        let item = makeItem("Brown loafers", .shoes, .brown, .smartCasual)

        do {
            let repo = SwiftDataClothingRepository(container: try ModelContainerFactory.make(storeURL: url))
            try repo.insert(item)
        }
        let reopened = SwiftDataClothingRepository(container: try ModelContainerFactory.make(storeURL: url))
        #expect(try reopened.allItems().map(\.id) == [item.id])
    }

    @Test func returnsNewestFirst() throws {
        let repo = SwiftDataClothingRepository(container: try ModelContainerFactory.make(inMemory: true))
        let old = makeItem("Old", .tops, .white, .casual, added: .now.addingTimeInterval(-100))
        let new = makeItem("New", .tops, .white, .casual)
        try repo.insert(old)
        try repo.insert(new)
        #expect(try repo.allItems().map(\.name) == ["New", "Old"])
    }
}

// MARK: - Wardrobe store

@MainActor
struct WardrobeStoreTests {
    private func makeStore() throws -> (WardrobeStore, LocalImageStore) {
        let images = LocalImageStore(baseDirectory: tempDirectory())
        let repo = SwiftDataClothingRepository(container: try ModelContainerFactory.make(inMemory: true))
        return (WardrobeStore(repository: repo, imageStore: images), images)
    }

    @Test func addSavesPhotoFilesAndRecord() throws {
        let (store, images) = try makeStore()
        let item = try store.add(completeDraft(), photo: samplePhoto(), status: .manual)
        #expect(store.items == [item])
        #expect(try images.load(item.imagePath) == Data([1, 2, 3]))
        #expect(try images.load(item.thumbnailPath) == Data([4, 5]))
    }

    @Test func addRejectsIncompleteDraft() throws {
        let (store, images) = try makeStore()
        var draft = completeDraft()
        draft.formality = nil
        #expect(throws: WardrobeError.incomplete(["casual or formal"])) {
            try store.add(draft, photo: samplePhoto(), status: .manual)
        }
        #expect(store.items.isEmpty)
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: images.baseDirectory.path(percentEncoded: false))) ?? []
        #expect(leftovers.isEmpty)
    }

    @Test func deleteRemovesRecordAndPhotos() throws {
        let (store, images) = try makeStore()
        let item = try store.add(completeDraft(), photo: samplePhoto(), status: .manual)
        try store.delete(item)
        #expect(store.items.isEmpty)
        #expect(!images.exists(item.imagePath))
        #expect(!images.exists(item.thumbnailPath))
    }

    @Test func deleteToleratesMissingPhotoFiles() throws {
        let (store, images) = try makeStore()
        let item = try store.add(completeDraft(), photo: samplePhoto(), status: .manual)
        try images.delete(item.imagePath)
        try store.delete(item)
        #expect(store.items.isEmpty)
    }

    @Test func editingAcceptedSuggestionMarksItEdited() throws {
        let (store, _) = try makeStore()
        let item = try store.add(completeDraft(), photo: samplePhoto(), status: .suggestedAccepted)
        var draft = ClothingDraft(item: item)
        draft.primaryColor = .beige
        let updated = try store.update(item, with: draft)
        #expect(updated.primaryColor == .beige)
        #expect(updated.aiStatus == .suggestedEdited)
    }

    @Test func toggleFavoritePersists() throws {
        let (store, _) = try makeStore()
        let item = try store.add(completeDraft(), photo: samplePhoto(), status: .manual)
        try store.toggleFavorite(item)
        store.reload()
        #expect(store.items.first?.isFavorite == true)
    }
}

// MARK: - Draft rules

struct ClothingDraftTests {
    @Test func reportsMissingFields() {
        #expect(ClothingDraft().missingFields == ["name", "category", "main colour", "casual or formal"])
        #expect(completeDraft().isComplete)
    }

    @Test func whitespaceNameIsMissing() {
        var draft = completeDraft()
        draft.name = "   "
        #expect(draft.missingFields == ["name"])
    }

    @Test func secondaryColoursExcludePrimaryAndDuplicates() {
        var draft = completeDraft()
        draft.secondaryColors = [.navy, .white, .white]
        #expect(draft.normalizedSecondaryColors == [.white])
    }

    @Test func statusReflectsUserCorrections() {
        let suggestion = completeDraft()
        var corrected = suggestion
        corrected.category = .outerwear
        #expect(ClothingDraft.status(for: suggestion, suggestion: suggestion, analysisFailure: nil) == .suggestedAccepted)
        #expect(ClothingDraft.status(for: corrected, suggestion: suggestion, analysisFailure: nil) == .suggestedEdited)
        #expect(ClothingDraft.status(for: corrected, suggestion: nil, analysisFailure: .analysisUnavailable) == .analysisUnavailable)
        #expect(ClothingDraft.status(for: corrected, suggestion: nil, analysisFailure: nil) == .manual)
    }

    @Test func draftFromAnalysisUsesMeasuredColours() {
        let analysis = ClothingAnalysis(
            name: "Light blue shirt", category: .tops, pattern: .solid, formality: .smartCasual,
            colors: [ColorShare(color: .lightBlue, share: 0.7), ColorShare(color: .white, share: 0.2)],
            visionLabels: [], source: .onDeviceModel
        )
        let draft = ClothingDraft(analysis: analysis)
        #expect(draft.primaryColor == .lightBlue)
        #expect(draft.secondaryColors == [.white])
        #expect(draft.isComplete)
    }
}

// MARK: - Search and filter

struct WardrobeQueryTests {
    let items = [
        makeItem("Light blue oxford", .tops, .lightBlue, .smartCasual, added: .now.addingTimeInterval(-30)),
        makeItem("Dark jeans", .bottoms, .navy, .casual, secondary: [.blue], favorite: true, added: .now.addingTimeInterval(-20)),
        makeItem("Brown loafers", .shoes, .brown, .smartCasual, added: .now.addingTimeInterval(-10)),
    ]

    @Test func filtersByCategory() {
        var query = WardrobeQuery()
        query.category = .shoes
        #expect(query.apply(to: items).map(\.name) == ["Brown loafers"])
    }

    @Test func colourFilterIncludesSecondaryColours() {
        var query = WardrobeQuery()
        query.color = .blue
        #expect(query.apply(to: items).map(\.name) == ["Dark jeans"])
    }

    @Test func searchMatchesAllTermsAcrossAttributes() {
        var query = WardrobeQuery()
        query.searchText = "smart brown"
        #expect(query.apply(to: items).map(\.name) == ["Brown loafers"])
        query.searchText = "LIGHT BLUE"
        #expect(query.apply(to: items).map(\.name) == ["Light blue oxford"])
        query.searchText = "velvet"
        #expect(query.apply(to: items).isEmpty)
    }

    @Test func favouritesOnly() {
        var query = WardrobeQuery()
        query.favoritesOnly = true
        #expect(query.apply(to: items).map(\.name) == ["Dark jeans"])
    }

    @Test func sorts() {
        var query = WardrobeQuery()
        #expect(query.apply(to: items).map(\.name) == ["Brown loafers", "Dark jeans", "Light blue oxford"])
        query.sort = .name
        #expect(query.apply(to: items).map(\.name) == ["Brown loafers", "Dark jeans", "Light blue oxford"])
        query.sort = .category
        #expect(query.apply(to: items).map(\.category) == [.tops, .bottoms, .shoes])
    }
}

// MARK: - Re-analysis keeps user edits

@MainActor
struct AddClothingModelTests {
    struct FakeAnalysis: ClothingAnalysisService {
        let result: ClothingAnalysis
        func analyze(_ image: CGImage, cutout: CGImage?) async throws -> ClothingAnalysis { result }
    }

    struct FailingAnalysis: ClothingAnalysisService {
        func analyze(_ image: CGImage, cutout: CGImage?) async throws -> ClothingAnalysis { throw ClothingAnalysisError.notClothing }
    }

    private let shirt = ClothingAnalysis(
        name: "Blue shirt", category: .tops, pattern: .solid, formality: .smartCasual,
        colors: [ColorShare(color: .blue, share: 0.9)], visionLabels: [], source: .onDeviceModel
    )

    private func pngData() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20))
        return renderer.pngData { ctx in
            UIColor.blue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        }
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<200 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    @Test func suggestionFillsFormAndUserCorrectionSurvivesReanalysis() async {
        let model = AddClothingModel(processor: ImageProcessor(), segmenter: NoCutoutSegmenter(), analysisService: FakeAnalysis(result: shirt), availabilityProvider: { .available })
        model.load(imageData: pngData())
        await waitUntil { model.analysis == .suggested(.onDeviceModel) }
        #expect(model.draft.name == "Blue shirt")
        #expect(model.draft.formality == .smartCasual)

        model.draft.formality = .formal
        model.reanalyze()
        await waitUntil { model.analysis == .suggested(.onDeviceModel) }
        #expect(model.draft.formality == .formal, "User edit is preserved")
        #expect(model.canSave)
    }

    @Test func analysisFailureLeavesManualEntryAvailable() async {
        let model = AddClothingModel(processor: ImageProcessor(), segmenter: NoCutoutSegmenter(), analysisService: FailingAnalysis(), availabilityProvider: { .deviceNotEligible })
        model.load(imageData: pngData())
        await waitUntil { if case .failed = model.analysis { true } else { false } }
        #expect(model.preparedPhoto != nil)
        #expect(!model.canSave)
        model.draft = completeDraft()
        #expect(model.canSave)
    }
}
