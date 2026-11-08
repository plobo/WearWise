import Foundation
import Observation
import SwiftData

/// Composition root: builds and owns the app's long-lived services.
@MainActor
@Observable
final class AppDependencies {
    let wardrobe: WardrobeStore
    let outfits: OutfitStore
    let explanations: OutfitExplanationProvider
    let analysisService: any ClothingAnalysisService
    let imageProcessor: ImageProcessor
    let segmenter: any ForegroundSegmenting
    /// Set when persistent storage couldn't be opened and the app fell back to memory.
    let storageWarning: String?

    @ObservationIgnored private let container: ModelContainer

    init(
        container: ModelContainer,
        imageStore: LocalImageStore,
        analysisService: any ClothingAnalysisService = DefaultClothingAnalysisService(),
        imageProcessor: ImageProcessor = ImageProcessor(),
        segmenter: any ForegroundSegmenting = ForegroundSegmenter(),
        storageWarning: String? = nil
    ) {
        self.container = container
        self.analysisService = analysisService
        self.imageProcessor = imageProcessor
        self.segmenter = segmenter
        self.storageWarning = storageWarning
        wardrobe = WardrobeStore(repository: SwiftDataClothingRepository(container: container), imageStore: imageStore)
        let outfits = OutfitStore(repository: SwiftDataOutfitRepository(container: container))
        self.outfits = outfits
        explanations = OutfitExplanationProvider()
        wardrobe.onItemDeleted = { itemID in try outfits.removeOutfits(containing: itemID) }
        #if DEBUG
        DebugSampleWardrobe.seedIfRequested(wardrobe)
        DebugSampleWardrobe.seedOutfitsIfRequested(outfits, wardrobe: wardrobe)
        #endif
    }

    static func live() -> AppDependencies {
        let imageStore = (try? LocalImageStore.appDefault())
            ?? LocalImageStore(baseDirectory: FileManager.default.temporaryDirectory.appending(path: "ClothingImages"))
        do {
            return AppDependencies(container: try ModelContainerFactory.make(), imageStore: imageStore)
        } catch {
            // Keep the app usable; warn that changes won't persist.
            let fallback = try! ModelContainerFactory.make(inMemory: true)
            return AppDependencies(
                container: fallback,
                imageStore: imageStore,
                storageWarning: "Your wardrobe couldn't be opened. Changes made now won't be saved."
            )
        }
    }
}
