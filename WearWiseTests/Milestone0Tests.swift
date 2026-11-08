import Foundation
import Testing
@testable import WearWise

struct ColorNamerTests {
    @Test(arguments: [
        (0.02, 0.02, 0.02, ClothingColor.black),
        (0.98, 0.98, 0.97, .white),
        (0.5, 0.5, 0.52, .grey),
        (0.12, 0.16, 0.33, .navy),
        (0.62, 0.74, 0.88, .lightBlue),
        (0.15, 0.35, 0.75, .blue),
        (0.84, 0.76, 0.62, .beige),
        (0.45, 0.29, 0.17, .brown),
        (0.80, 0.15, 0.15, .red),
        (0.45, 0.10, 0.17, .burgundy),
        (0.18, 0.55, 0.30, .green),
    ])
    func namesReferenceColours(r: Double, g: Double, b: Double, expected: ClothingColor) {
        #expect(ColorNamer.name(red: r, green: g, blue: b) == expected)
    }

    @Test func everySwatchMapsBackToItself() {
        for color in ClothingColor.allCases {
            let s = color.swatch
            #expect(ColorNamer.name(red: s.red, green: s.green, blue: s.blue) == color, "\(color)")
        }
    }
}

struct DominantColorAnalyzerTests {
    typealias RGB = DominantColorAnalyzer.RGB

    /// A navy garment in the middle of a white background.
    private func garmentOnBackground(garment: RGB, background: RGB, size: Int = 40) -> [RGB] {
        (0..<size * size).map { i in
            let x = i % size, y = i / size
            let inGarment = x >= size / 4 && x < size * 3 / 4 && y >= size / 6 && y < size * 5 / 6
            return inGarment ? garment : background
        }
    }

    @Test func ignoresBackgroundColour() {
        let pixels = garmentOnBackground(garment: RGB(r: 0.12, g: 0.16, b: 0.33), background: RGB(r: 1, g: 1, b: 1))
        let result = DominantColorAnalyzer.dominantColors(pixels: pixels, width: 40, height: 40)
        #expect(result.first?.color == .navy)
        #expect((result.first?.share ?? 0) > 0.8)
    }

    @Test func whiteGarmentOnWhiteBackgroundStillReportsWhite() {
        let white = RGB(r: 0.97, g: 0.97, b: 0.97)
        let pixels = garmentOnBackground(garment: white, background: white)
        let result = DominantColorAnalyzer.dominantColors(pixels: pixels, width: 40, height: 40)
        #expect(result.first?.color == .white)
    }

    @Test func rejectsMismatchedPixelCount() {
        #expect(DominantColorAnalyzer.dominantColors(pixels: [], width: 10, height: 10).isEmpty)
    }
}

struct VisionLabelCategoryMapperTests {
    private func labels(_ pairs: (String, Double)...) -> [VisionLabel] {
        pairs.map { VisionLabel(identifier: $0.0, confidence: $0.1) }
    }

    @Test func mapsCommonLabels() {
        #expect(VisionLabelCategoryMapper.category(for: labels(("jeans", 0.8))) == .bottoms)
        #expect(VisionLabelCategoryMapper.category(for: labels(("sneaker", 0.7))) == .shoes)
        #expect(VisionLabelCategoryMapper.category(for: labels(("blazer", 0.6))) == .outerwear)
        #expect(VisionLabelCategoryMapper.category(for: labels(("t_shirt", 0.6))) == .tops)
    }

    @Test func usesHighestConfidenceLabelFirst() {
        let result = VisionLabelCategoryMapper.category(for: labels(("shirt", 0.3), ("shoes", 0.9)))
        #expect(result == .shoes)
    }

    @Test func unknownLabelsGiveNoCategory() {
        #expect(VisionLabelCategoryMapper.category(for: labels(("dog", 0.9))) == nil)
    }
}

struct FallbackAnalysisTests {
    @Test func buildsNameFromColourAndCategory() throws {
        let analysis = try DefaultClothingAnalysisService.fallback(
            labels: [VisionLabel(identifier: "jeans", confidence: 0.8)],
            colors: [ColorShare(color: .navy, share: 0.9)],
            reason: "AI unavailable"
        )
        #expect(analysis.name == "Navy bottoms")
        #expect(analysis.category == .bottoms)
        #expect(analysis.pattern == .solid)
        #expect(analysis.formality == nil)
        #expect(analysis.source == .visionOnly(reason: "AI unavailable"))
    }

    @Test func rejectsPhotosThatAreNotClothing() {
        #expect(throws: ClothingAnalysisError.self) {
            try DefaultClothingAnalysisService.fallback(
                labels: [VisionLabel(identifier: "dog", confidence: 0.9)],
                colors: [],
                reason: "AI unavailable"
            )
        }
    }

    @Test func promptContainsEvidenceOnly() {
        let prompt = FoundationModelsClothingInterpreter.prompt(
            labels: [VisionLabel(identifier: "t_shirt", confidence: 0.82)],
            colors: [ColorShare(color: .lightBlue, share: 0.6)]
        )
        #expect(prompt.contains("t shirt (82%)"))
        #expect(prompt.contains("light blue 60%"))
    }
}

struct LocalImageStoreTests {
    @Test func savesLoadsAndDeletes() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = LocalImageStore(baseDirectory: dir)
        let data = Data([1, 2, 3, 4])

        let path = try store.save(data, fileName: "a.jpg")
        #expect(!path.hasPrefix("/"), "Stores a relative path")
        #expect(try store.load(path) == data)

        try store.delete(path)
        #expect(throws: (any Error).self) { try store.load(path) }
        // Deleting a missing file is not an error.
        try store.delete(path)
    }
}

struct LocalImageStorePathTests {
    /// The real store lives under "Application Support", which contains a space.
    @Test func handlesDirectoriesWithSpaces() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "With Space \(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = LocalImageStore(baseDirectory: dir)
        let path = try store.save(Data([9]), fileName: "x.jpg")
        #expect(store.exists(path))
        try store.delete(path)
        #expect(!store.exists(path))
    }
}
