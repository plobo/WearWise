import CoreGraphics
import Foundation

/// Application-level interface for analysing a clothing photo.
protocol ClothingAnalysisService: Sendable {
    func analyze(_ image: CGImage) async throws -> ClothingAnalysis
}

enum ClothingAnalysisError: LocalizedError {
    case notClothing

    var errorDescription: String? {
        "This photo doesn't look like a clothing item. You can still enter details yourself."
    }
}

/// Vision + colour sampling, then on-device model interpretation, with a deterministic fallback.
struct DefaultClothingAnalysisService: ClothingAnalysisService {
    var classifier = VisionClassifier()
    var interpreter = FoundationModelsClothingInterpreter()

    func analyze(_ image: CGImage) async throws -> ClothingAnalysis {
        let labels = try await classifier.classify(image)
        try Task.checkCancellation()
        let colors = await Self.measureColors(image)
        try Task.checkCancellation()

        do {
            let generated = try await interpreter.interpret(labels: labels, colors: colors)
            var analysis = generated.toDomain(colors: colors, labels: labels)
            // Trust the measured colours for pattern when the model had no evidence.
            if analysis.pattern == .unknown, let top = colors.first, top.share > 0.75 {
                analysis.pattern = .solid
            }
            return analysis
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as AIError {
            return try Self.fallback(labels: labels, colors: colors, reason: error.localizedDescription)
        }
    }

    @concurrent
    private static func measureColors(_ image: CGImage) async -> [ColorShare] {
        DominantColorAnalyzer.dominantColors(in: image)
    }

    static func fallback(labels: [VisionLabel], colors: [ColorShare], reason: String) throws -> ClothingAnalysis {
        let category = VisionLabelCategoryMapper.category(for: labels)
        if category == nil, !labels.isEmpty, !VisionLabelCategoryMapper.looksLikeClothing(labels) {
            throw ClothingAnalysisError.notClothing
        }
        let resolved = category ?? .other
        let colorName = colors.first?.color.displayName
        let typeName = resolved == .other ? "item" : resolved.displayName.lowercased()
        let name = [colorName, typeName].compactMap { $0 }.joined(separator: " ")
        var pattern = VisionLabelCategoryMapper.pattern(for: labels)
        if pattern == .unknown, let top = colors.first, top.share > 0.75 { pattern = .solid }
        return ClothingAnalysis(
            name: name.prefix(1).uppercased() + name.dropFirst(),
            category: resolved,
            pattern: pattern,
            formality: nil,
            colors: colors,
            visionLabels: labels,
            source: .visionOnly(reason: reason)
        )
    }
}
