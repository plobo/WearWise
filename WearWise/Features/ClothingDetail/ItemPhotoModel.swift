import CoreGraphics
import Foundation
import Observation

/// Removes or restores the background of an item that's already in the wardrobe.
@MainActor
@Observable
final class ItemPhotoModel {
    enum State: Equatable {
        case idle
        case working
        case failed(String)
    }

    /// A colour change the cut-out suggests. Never applied without the user's say-so.
    struct ColorSuggestion: Equatable {
        let itemID: UUID
        let current: ClothingColor
        let suggested: ClothingColor
    }

    private(set) var state: State = .idle
    var colorSuggestion: ColorSuggestion?

    private let processor: ImageProcessor
    private let segmenter: any ForegroundSegmenting

    init(processor: ImageProcessor, segmenter: any ForegroundSegmenting) {
        self.processor = processor
        self.segmenter = segmenter
    }

    var isWorking: Bool { state == .working }

    func removeBackground(of item: ClothingItem, in wardrobe: WardrobeStore) async {
        guard !isWorking else { return }
        state = .working
        do {
            let original = try wardrobe.imageStore.load(item.imagePath)
            let prepared = try await processor.prepare(original)
            // Segmentation may be unsupported (e.g. the Simulator); treat errors like "no subject found".
            guard let cutout = try? await segmenter.cutout(from: prepared.cgImage) else {
                state = .failed("Couldn't separate the item from the background in this photo.")
                return
            }
            let updated = try wardrobe.attachCutout(cutout, to: item)
            let measured = await Self.mainColor(of: cutout.cgImage)
            if let measured, measured != updated.primaryColor {
                colorSuggestion = ColorSuggestion(itemID: item.id, current: updated.primaryColor, suggested: measured)
            }
            state = .idle
        } catch {
            state = .failed("The photo couldn't be updated. \(error.localizedDescription)")
        }
    }

    func restoreOriginal(of item: ClothingItem, in wardrobe: WardrobeStore) async {
        guard !isWorking else { return }
        state = .working
        do {
            let original = try wardrobe.imageStore.load(item.imagePath)
            let prepared = try await processor.prepare(original)
            try wardrobe.removeCutout(from: item, originalThumbnail: prepared.thumbnailData)
            state = .idle
        } catch {
            state = .failed("The original photo couldn't be restored. \(error.localizedDescription)")
        }
    }

    /// Applies the suggested main colour, keeping every other attribute as the user set it.
    func acceptColorSuggestion(in wardrobe: WardrobeStore) {
        guard let suggestion = colorSuggestion, let item = wardrobe.item(id: suggestion.itemID) else { return }
        colorSuggestion = nil
        var draft = ClothingDraft(item: item)
        draft.primaryColor = suggestion.suggested
        draft.secondaryColors.removeAll { $0 == suggestion.suggested }
        do {
            try wardrobe.update(item, with: draft)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func dismissError() {
        if case .failed = state { state = .idle }
    }

    @concurrent
    private static func mainColor(of cutout: CGImage) async -> ClothingColor? {
        DominantColorAnalyzer.dominantColors(inCutout: cutout).first?.color
    }
}
