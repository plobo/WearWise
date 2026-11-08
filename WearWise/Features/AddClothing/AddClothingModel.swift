import Foundation
import Observation
import UIKit

/// Coordinates: photo → preparation → optional on-device analysis → user review → save.
@MainActor
@Observable
final class AddClothingModel {
    enum PhotoState {
        case none
        case preparing
        case ready(ImageProcessor.Prepared, UIImage)
        case failed(String)
    }

    enum AnalysisState: Equatable {
        case idle
        case analyzing
        case suggested(ClothingAnalysis.Source)
        case failed(String)
    }

    var draft = ClothingDraft()
    private(set) var suggestion: ClothingDraft?
    private(set) var photo: PhotoState = .none
    private(set) var analysis: AnalysisState = .idle
    private(set) var aiAvailability: AIAvailability = .unknownUnavailable
    var saveError: String?

    private let processor: ImageProcessor
    private let analysisService: any ClothingAnalysisService
    private let availabilityProvider: @MainActor () -> AIAvailability
    private var analysisFailure: AIAnalysisStatus?
    private var work: Task<Void, Never>?

    init(
        processor: ImageProcessor,
        analysisService: any ClothingAnalysisService,
        availabilityProvider: @escaping @MainActor () -> AIAvailability = { AIAvailabilityChecker.current() }
    ) {
        self.processor = processor
        self.analysisService = analysisService
        self.availabilityProvider = availabilityProvider
        aiAvailability = availabilityProvider()
    }

    var preparedPhoto: ImageProcessor.Prepared? {
        if case .ready(let prepared, _) = photo { return prepared }
        return nil
    }

    var previewImage: UIImage? {
        if case .ready(_, let image) = photo { return image }
        return nil
    }

    var isAnalyzing: Bool { analysis == .analyzing }
    var canSave: Bool { preparedPhoto != nil && draft.isComplete && !isAnalyzing }

    /// Loads a new photo and automatically starts analysis.
    func load(imageData: Data) {
        work?.cancel()
        photo = .preparing
        analysis = .idle
        work = Task {
            do {
                let prepared = try await processor.prepare(imageData)
                try Task.checkCancellation()
                photo = .ready(prepared, UIImage(cgImage: prepared.cgImage))
                await runAnalysis(on: prepared)
            } catch is CancellationError {
                return
            } catch {
                photo = .failed(error.localizedDescription)
            }
        }
    }

    func photoLoadFailed() {
        photo = .failed("That photo couldn't be loaded. Try another one.")
    }

    func reanalyze() {
        guard let prepared = preparedPhoto, !isAnalyzing else { return }
        work?.cancel()
        work = Task { await runAnalysis(on: prepared) }
    }

    func cancel() {
        work?.cancel()
        work = nil
        if analysis == .analyzing { analysis = .idle }
    }

    private func runAnalysis(on prepared: ImageProcessor.Prepared) async {
        aiAvailability = availabilityProvider()
        analysis = .analyzing
        do {
            let result = try await analysisService.analyze(prepared.cgImage)
            try Task.checkCancellation()
            applySuggestion(ClothingDraft(analysis: result))
            analysis = .suggested(result.source)
            analysisFailure = nil
        } catch is CancellationError {
            if analysis == .analyzing { analysis = .idle }
        } catch {
            analysis = .failed(error.localizedDescription)
            analysisFailure = aiAvailability.isAvailable ? .analysisFailed : .analysisUnavailable
        }
    }

    /// Fills only the fields the user hasn't already set, so re-analysis never overwrites their edits.
    private func applySuggestion(_ new: ClothingDraft) {
        let previous = suggestion
        func untouched<T: Equatable>(_ current: T, _ old: T?, empty: T) -> Bool {
            current == empty || current == old
        }
        if untouched(draft.name, previous?.name, empty: "") { draft.name = new.name }
        if untouched(draft.category, previous?.category, empty: nil) { draft.category = new.category }
        if untouched(draft.primaryColor, previous?.primaryColor, empty: nil) { draft.primaryColor = new.primaryColor }
        if untouched(draft.secondaryColors, previous?.secondaryColors, empty: []) { draft.secondaryColors = new.secondaryColors }
        if untouched(draft.pattern, previous?.pattern, empty: .unknown) { draft.pattern = new.pattern }
        if untouched(draft.formality, previous?.formality, empty: nil) { draft.formality = new.formality }
        suggestion = new
    }

    func save(to wardrobe: WardrobeStore) -> ClothingItem? {
        guard let prepared = preparedPhoto else {
            saveError = "Add a photo first."
            return nil
        }
        let status = ClothingDraft.status(for: draft, suggestion: suggestion, analysisFailure: analysisFailure)
        do {
            return try wardrobe.add(draft, photo: prepared, status: status)
        } catch {
            saveError = error.localizedDescription
            return nil
        }
    }
}
