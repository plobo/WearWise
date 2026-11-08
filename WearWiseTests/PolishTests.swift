import CoreGraphics
import Foundation
import Testing
import UIKit
@testable import WearWise

// MARK: - Short reasons

struct ReasonSummaryTests {
    let shirt = makeItem("Light blue oxford", .tops, .lightBlue, .smartCasual)
    let chinos = makeItem("Beige chinos", .bottoms, .beige, .smartCasual)
    let loafers = makeItem("Brown loafers", .shoes, .brown, .smartCasual)
    let blazer = makeItem("Navy blazer", .outerwear, .navy, .smartCasual)

    @Test func summaryIsColourShoesAndFormality() {
        let s = OutfitMatcher.evaluate(top: shirt, bottom: chinos, shoes: loafers)!
        #expect(s.summary == "Beige pants keep the light blue top in focus. Brown shoes keep it grounded. All smart casual.")
    }

    @Test func extrasStayOutOfTheSummaryButReachTheModel() {
        guard case .suggestions(let list) = OutfitMatcher.match(top: shirt, wardrobe: [shirt, chinos, loafers, blazer]),
              let s = list.first else {
            Issue.record("Expected suggestions")
            return
        }
        #expect(!s.summary.contains("blazer"))
        let input = OutfitExplanationInput(s)
        #expect(input.fallbackText == s.summary)
        #expect(input.factsText.contains("The navy blazer works over it when it's cooler"))
        #expect(FoundationModelsOutfitExplainer.prompt(for: input).contains("navy blazer works over it"))
    }

    @Test func dressSummaryKeepsBothSentences() {
        let dress = makeItem("Burgundy dress", .dresses, .burgundy, .smartCasual)
        let s = OutfitMatcher.evaluate(top: dress, bottom: nil, shoes: loafers)!
        #expect(s.summary == "Brown shoes let the burgundy dress lead. All smart casual.")
    }

    @Test func summaryNeverExceedsThreeSentences() {
        var s = OutfitMatcher.evaluate(top: shirt, bottom: chinos, shoes: loafers)!
        s.recencyNote = "You wore the beige chinos today"
        s.extraReasons = ["A", "B", "C"]
        #expect(s.summary.split(separator: ".").count == 3)
    }
}

// MARK: - Removing the background of existing items

@MainActor
struct ItemPhotoModelTests {
    /// A real JPEG so the image pipeline can decode it.
    private func jpeg() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 60, height: 60)).jpegData(withCompressionQuality: 0.9) { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 60, height: 60))
        }
    }

    /// A wardrobe with one black item whose photo is a real JPEG and whose thumbnail is a JPEG.
    private func makeWardrobe() throws -> (WardrobeStore, ClothingItem) {
        let images = LocalImageStore(baseDirectory: tempDirectory())
        let store = WardrobeStore(
            repository: SwiftDataClothingRepository(container: try ModelContainerFactory.make(inMemory: true)),
            imageStore: images
        )
        var draft = completeDraft("Black shirt")
        draft.category = .tops
        draft.primaryColor = .black
        let data = jpeg()
        let photo = ImageProcessor.Prepared(cgImage: UIImage(data: data)!.cgImage!, jpegData: data, thumbnailData: data)
        return (store, try store.add(draft, photo: photo, status: .manual))
    }

    @Test func removingBackgroundStoresCutoutAndSuggestsMeasuredColour() async throws {
        let (store, item) = try makeWardrobe()
        let model = ItemPhotoModel(processor: ImageProcessor(), segmenter: FixedCutoutSegmenter())

        await model.removeBackground(of: item, in: store)

        let updated = try #require(store.item(id: item.id))
        #expect(model.state == .idle)
        #expect(updated.cutoutPath != nil)
        #expect(updated.thumbnailPath.hasSuffix(".png"))
        #expect(store.imageStore.exists(updated.imagePath), "Original kept")
        #expect(!store.imageStore.exists(item.thumbnailPath), "Old thumbnail removed")
        #expect(updated.primaryColor == .black, "Colour isn't changed without asking")
        #expect(model.colorSuggestion == .init(itemID: item.id, current: .black, suggested: .navy))
    }

    @Test func acceptingColourSuggestionChangesOnlyTheColour() async throws {
        let (store, item) = try makeWardrobe()
        let model = ItemPhotoModel(processor: ImageProcessor(), segmenter: FixedCutoutSegmenter())
        await model.removeBackground(of: item, in: store)

        model.acceptColorSuggestion(in: store)
        let updated = try #require(store.item(id: item.id))
        #expect(updated.primaryColor == .navy)
        #expect(updated.name == "Black shirt")
        #expect(updated.formality == item.formality)
        #expect(model.colorSuggestion == nil)
    }

    @Test func noSuggestionWhenColourAlreadyMatches() async throws {
        let (store, item) = try makeWardrobe()
        let model = ItemPhotoModel(processor: ImageProcessor(), segmenter: FixedCutoutSegmenter(color: .black))
        await model.removeBackground(of: item, in: store)
        #expect(model.colorSuggestion == nil)
    }

    @Test func segmentationFailureLeavesItemUntouched() async throws {
        let (store, item) = try makeWardrobe()
        let model = ItemPhotoModel(processor: ImageProcessor(), segmenter: ThrowingSegmenter())
        await model.removeBackground(of: item, in: store)
        #expect(model.state == .failed("Couldn't separate the item from the background in this photo."))
        #expect(store.item(id: item.id) == item)
    }

    @Test func restoringOriginalRemovesCutoutFiles() async throws {
        let (store, item) = try makeWardrobe()
        let model = ItemPhotoModel(processor: ImageProcessor(), segmenter: FixedCutoutSegmenter())
        await model.removeBackground(of: item, in: store)
        let withCutout = try #require(store.item(id: item.id))
        let cutoutPath = try #require(withCutout.cutoutPath)

        await model.restoreOriginal(of: withCutout, in: store)

        let restored = try #require(store.item(id: item.id))
        #expect(restored.cutoutPath == nil)
        #expect(restored.thumbnailPath.hasSuffix(".jpg"))
        #expect(store.imageStore.exists(restored.thumbnailPath))
        #expect(!store.imageStore.exists(cutoutPath))
        #expect(!store.imageStore.exists(withCutout.thumbnailPath))
        #expect(store.imageStore.exists(restored.imagePath))
    }
}
