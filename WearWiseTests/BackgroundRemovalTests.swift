import CoreGraphics
import Foundation
import SwiftData
import Testing
import UIKit
@testable import WearWise

// MARK: - Test doubles

struct NoCutoutSegmenter: ForegroundSegmenting {
    func cutout(from image: CGImage) async throws -> ForegroundSegmenter.Cutout? { nil }
}

struct ThrowingSegmenter: ForegroundSegmenting {
    struct Unsupported: Error {}
    func cutout(from image: CGImage) async throws -> ForegroundSegmenter.Cutout? { throw Unsupported() }
}

/// Returns a fixed cut-out: an item of one colour on a transparent background.
struct FixedCutoutSegmenter: ForegroundSegmenting {
    var color: UIColor = UIColor(red: 0.12, green: 0.16, blue: 0.33, alpha: 1)

    func cutout(from image: CGImage) async throws -> ForegroundSegmenter.Cutout? {
        let cg = Self.transparentImage(itemColor: color)
        let png = UIImage(cgImage: cg).pngData()!
        return ForegroundSegmenter.Cutout(cgImage: cg, pngData: png, thumbnailPNGData: png)
    }

    static func transparentImage(itemColor: UIColor, size: CGFloat = 40) -> CGImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format).image { ctx in
            itemColor.setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 4, y: 4, width: size - 8, height: size - 8))
        }.cgImage!
    }
}

/// Records which image the analysis was given, and reports colours from it.
final class RecordingAnalysis: ClothingAnalysisService, @unchecked Sendable {
    private let lock = NSLock()
    private var _cutoutCalls: [Bool] = []
    var cutoutCalls: [Bool] { lock.withLock { _cutoutCalls } }

    func analyze(_ image: CGImage, cutout: CGImage?) async throws -> ClothingAnalysis {
        lock.withLock { _cutoutCalls.append(cutout != nil) }
        let colors = cutout.map { DominantColorAnalyzer.dominantColors(inCutout: $0) } ?? DominantColorAnalyzer.dominantColors(in: image)
        return ClothingAnalysis(
            name: "Shirt", category: .tops, pattern: .solid, formality: .casual,
            colors: colors, visionLabels: [], source: .visionOnly(reason: "test")
        )
    }
}

// MARK: - Colour measurement

struct CutoutColorTests {
    typealias RGBA = DominantColorAnalyzer.RGBA

    @Test func ignoresTransparentPixels() {
        let navy = RGBA(r: 0.12, g: 0.16, b: 0.33, a: 1)
        let clearWhite = RGBA(r: 1, g: 1, b: 1, a: 0)
        let pixels = Array(repeating: navy, count: 100) + Array(repeating: clearWhite, count: 900)
        let colors = DominantColorAnalyzer.dominantColors(cutoutPixels: pixels)
        #expect(colors == [ColorShare(color: .navy, share: 1)])
    }

    @Test func whiteItemOnTransparentBackgroundIsWhite() {
        let image = FixedCutoutSegmenter.transparentImage(itemColor: .white)
        #expect(DominantColorAnalyzer.dominantColors(inCutout: image).first?.color == .white)
    }

    @Test func reportsTwoColourItems() {
        let navy = RGBA(r: 0.12, g: 0.16, b: 0.33, a: 1)
        let white = RGBA(r: 0.97, g: 0.97, b: 0.97, a: 1)
        let pixels = Array(repeating: navy, count: 600) + Array(repeating: white, count: 400)
        let colors = DominantColorAnalyzer.dominantColors(cutoutPixels: pixels)
        #expect(colors.map(\.color) == [.navy, .white])
    }

    @Test func opaqueFractionOfEmptyImageIsZero() {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let empty = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20), format: format).image { _ in }.cgImage!
        #expect(DominantColorAnalyzer.opaqueFraction(in: empty) == 0)
    }
}

struct ShadeMergingTests {
    @Test func foldsSmallShadesIntoMainColour() {
        // Shadows on a navy shirt read partly as blue.
        let shares = DominantColorAnalyzer.shares(from: [.navy: 70, .blue: 20, .white: 10], minimumShare: 0.05)
        #expect(shares.first == ColorShare(color: .navy, share: 0.9))
        #expect(shares.map(\.color) == [.navy, .white])
    }

    @Test func keepsLargeSecondShadeAsRealSecondColour() {
        let shares = DominantColorAnalyzer.shares(from: [.navy: 55, .lightBlue: 45], minimumShare: 0.1)
        #expect(shares.map(\.color) == [.navy, .lightBlue])
    }

    @Test func doesNotMergeAcrossFamilies() {
        let shares = DominantColorAnalyzer.shares(from: [.navy: 80, .beige: 20], minimumShare: 0.1)
        #expect(shares.map(\.color) == [.navy, .beige])
    }
}

// MARK: - Persistence

@MainActor
struct CutoutPersistenceTests {
    @Test func storesCutoutAndUsesItForThumbnail() async throws {
        let images = LocalImageStore(baseDirectory: tempDirectory())
        let store = WardrobeStore(
            repository: SwiftDataClothingRepository(container: try ModelContainerFactory.make(inMemory: true)),
            imageStore: images
        )
        let cutout = try #require(try await FixedCutoutSegmenter().cutout(from: samplePhoto().cgImage))
        let item = try store.add(completeDraft(), photo: samplePhoto(), cutout: cutout, status: .manual)

        let cutoutPath = try #require(item.cutoutPath)
        #expect(item.displayImagePath == cutoutPath)
        #expect(item.thumbnailPath.hasSuffix(".png"))
        #expect(try images.load(cutoutPath) == cutout.pngData)
        #expect(try images.load(item.imagePath) == Data([1, 2, 3]), "Original photo is kept")

        try store.delete(item)
        #expect(!images.exists(cutoutPath))
        #expect(!images.exists(item.imagePath))
        #expect(!images.exists(item.thumbnailPath))
    }

    @Test func itemsWithoutCutoutDisplayOriginal() throws {
        let item = makeItem("Tee", .tops, .white, .casual)
        #expect(item.cutoutPath == nil)
        #expect(item.displayImagePath == item.imagePath)
    }

    @Test func migratesVersion1StoreWithoutLosingItems() throws {
        let dir = tempDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "wardrobe.store")
        let item = makeItem("Brown loafers", .shoes, .brown, .smartCasual)

        // Write with the old schema only.
        do {
            let v1Schema = Schema(versionedSchema: WardrobeSchemaV1.self)
            let v1 = try ModelContainer(for: v1Schema, configurations: ModelConfiguration(schema: v1Schema, url: url))
            v1.mainContext.insert(WardrobeSchemaV1.ClothingItemRecord(item: item))
            try v1.mainContext.save()
        }

        // Reopen with the current schema and migration plan.
        let repo = SwiftDataClothingRepository(container: try ModelContainerFactory.make(storeURL: url))
        let migrated = try repo.allItems()
        #expect(migrated.map(\.id) == [item.id])
        #expect(migrated.first?.name == "Brown loafers")
        #expect(migrated.first?.cutoutPath == nil)
    }
}

// MARK: - Add flow

@MainActor
struct AddClothingBackgroundTests {
    private func pngData() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).pngData { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        }
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<300 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    @Test func usesCutoutColoursAndSavesCutout() async throws {
        let analysis = RecordingAnalysis()
        let model = AddClothingModel(processor: ImageProcessor(), segmenter: FixedCutoutSegmenter(), analysisService: analysis, availabilityProvider: { .available })
        model.load(imageData: pngData())
        await waitUntil { if case .suggested = model.analysis { true } else { false } }

        #expect(model.background == .removed)
        #expect(analysis.cutoutCalls == [true])
        // The photo is plain white, so navy can only come from the cut-out.
        #expect(model.draft.primaryColor == .navy)

        let store = WardrobeStore(
            repository: SwiftDataClothingRepository(container: try ModelContainerFactory.make(inMemory: true)),
            imageStore: LocalImageStore(baseDirectory: tempDirectory())
        )
        let item = try #require(model.save(to: store))
        #expect(item.cutoutPath != nil)
    }

    @Test func turningOffCutoutReanalysesFullPhotoAndSavesWithoutIt() async throws {
        let analysis = RecordingAnalysis()
        let model = AddClothingModel(processor: ImageProcessor(), segmenter: FixedCutoutSegmenter(), analysisService: analysis, availabilityProvider: { .available })
        model.load(imageData: pngData())
        await waitUntil { analysis.cutoutCalls.count == 1 && model.analysis != .analyzing }

        model.setUseCutout(false)
        await waitUntil { analysis.cutoutCalls.count == 2 && model.analysis != .analyzing }
        #expect(analysis.cutoutCalls == [true, false])
        #expect(model.activeCutout == nil)

        let store = WardrobeStore(
            repository: SwiftDataClothingRepository(container: try ModelContainerFactory.make(inMemory: true)),
            imageStore: LocalImageStore(baseDirectory: tempDirectory())
        )
        let item = try #require(model.save(to: store))
        #expect(item.cutoutPath == nil)
    }

    @Test func segmentationFailureFallsBackToFullPhoto() async {
        let analysis = RecordingAnalysis()
        let model = AddClothingModel(processor: ImageProcessor(), segmenter: ThrowingSegmenter(), analysisService: analysis, availabilityProvider: { .available })
        model.load(imageData: pngData())
        await waitUntil { if case .suggested = model.analysis { true } else { false } }

        #expect(model.background == .unavailable)
        #expect(analysis.cutoutCalls == [false])
        #expect(model.preparedPhoto != nil)
    }
}

// MARK: - Real Vision segmentation (device only)

/// Vision foreground segmentation can't create an inference context in the iOS Simulator on Intel Macs,
/// so this runs only on real hardware.
struct ForegroundSegmenterDeviceTests {
    static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    @Test(.enabled(if: !isSimulator, "Vision segmentation needs a real device"))
    func cutsOutShirtAndMeasuresItsColour() async throws {
        let size = CGSize(width: 600, height: 600)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let photo = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor(red: 0.93, green: 0.91, blue: 0.87, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let shirt = UIImage(systemName: "tshirt.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 380))!
                .withTintColor(UIColor(red: 0.12, green: 0.16, blue: 0.33, alpha: 1), renderingMode: .alwaysOriginal)
            shirt.draw(at: CGPoint(x: (size.width - shirt.size.width) / 2, y: (size.height - shirt.size.height) / 2))
        }.cgImage!

        let cutout = try #require(try await ForegroundSegmenter().cutout(from: photo), "Vision found no foreground subject")
        #expect(DominantColorAnalyzer.dominantColors(inCutout: cutout.cgImage).first?.color == .navy)
        #expect(cutout.cgImage.width < 600, "Cropped to the item")
    }
}
