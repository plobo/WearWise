import Foundation
import FoundationModels

enum AIError: LocalizedError, Equatable {
    case unavailable(AIAvailability)
    case contextTooLarge
    case refused
    case modelBusy
    case unsupportedLanguage
    case invalidOutput
    case generationFailed

    var errorDescription: String? {
        switch self {
        case .unavailable(let availability): availability.message
        case .contextTooLarge: "The request was too large for the on-device model."
        case .refused: "The on-device model declined to describe this image."
        case .modelBusy: "The on-device model is busy. Try again in a moment."
        case .unsupportedLanguage: "The on-device model doesn't support your device language yet."
        case .invalidOutput: "The AI returned something unusable."
        case .generationFailed: "AI analysis failed."
        }
    }
}

// MARK: - Generable schema (kept separate from domain types)

@Generable
enum GeneratedCategory {
    case tops, bottoms, dresses, outerwear, shoes, accessories, activewear, other
}

@Generable
enum GeneratedFormality {
    case casual, smartCasual, formal
}

@Generable
enum GeneratedPattern {
    case solid, striped, checked, floral, printed, other, unknown
}

@Generable(description: "Structured description of a single clothing item")
struct GeneratedClothingDescription {
    @Guide(description: "Short display name of 2 to 5 words combining colour and garment type, e.g. 'Light blue oxford shirt'. No brand names.")
    var name: String

    @Guide(description: "The wardrobe category that best fits the item")
    var category: GeneratedCategory

    @Guide(description: "Visible pattern. Use unknown unless the evidence mentions one; use solid if a single colour dominates.")
    var pattern: GeneratedPattern

    @Guide(description: "How dressy the item is: casual (t-shirts, jeans, sneakers), smartCasual (oxford shirts, chinos, loafers), formal (dress shirts, suit trousers, dress shoes)")
    var formality: GeneratedFormality
}

/// Turns Vision labels + measured colours into a structured description using the on-device model.
///
/// The iOS 26 Foundation Models API accepts text only, so the model never sees pixels:
/// it interprets evidence extracted by Vision and colour sampling.
struct FoundationModelsClothingInterpreter: Sendable {
    static let instructions = """
    You catalogue a single clothing item for a personal wardrobe app.
    You cannot see the photo. You receive labels from an image classifier and colours measured from the pixels.
    Use only that evidence. Do not invent brand, material, fabric, size, fit or price.
    If the evidence is weak, pick the most plausible category and keep the name generic.
    Use the measured colours in the name rather than guessing others.
    """

    func interpret(labels: [VisionLabel], colors: [ColorShare]) async throws -> GeneratedClothingDescription {
        let availability = AIAvailabilityChecker.current()
        guard availability.isAvailable else { throw AIError.unavailable(availability) }

        let session = LanguageModelSession(
            model: SystemLanguageModel(useCase: .contentTagging),
            instructions: Self.instructions
        )
        do {
            let response = try await session.respond(
                to: Self.prompt(labels: labels, colors: colors),
                generating: GeneratedClothingDescription.self,
                options: GenerationOptions(sampling: .greedy)
            )
            return response.content
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as LanguageModelSession.GenerationError {
            throw Self.map(error)
        } catch {
            throw AIError.generationFailed
        }
    }

    static func prompt(labels: [VisionLabel], colors: [ColorShare]) -> String {
        let labelText = labels.isEmpty
            ? "none"
            : labels.map { "\($0.identifier.replacingOccurrences(of: "_", with: " ")) (\(Int($0.confidence * 100))%)" }
                .joined(separator: ", ")
        let colorText = colors.isEmpty
            ? "unknown"
            : colors.map { "\($0.color.displayName.lowercased()) \(Int($0.share * 100))%" }.joined(separator: ", ")
        return """
        Image classifier labels: \(labelText)
        Measured garment colours: \(colorText)
        Describe this clothing item.
        """
    }

    static func map(_ error: LanguageModelSession.GenerationError) -> AIError {
        switch error {
        case .exceededContextWindowSize: .contextTooLarge
        case .assetsUnavailable: .unavailable(.modelNotReady)
        case .guardrailViolation, .refusal: .refused
        case .rateLimited, .concurrentRequests: .modelBusy
        case .unsupportedLanguageOrLocale: .unsupportedLanguage
        case .decodingFailure, .unsupportedGuide: .invalidOutput
        @unknown default: .generationFailed
        }
    }
}

// MARK: - Mapping to domain

extension GeneratedClothingDescription {
    func toDomain(colors: [ColorShare], labels: [VisionLabel]) -> ClothingAnalysis {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return ClothingAnalysis(
            name: trimmed.isEmpty ? "New item" : String(trimmed.prefix(60)),
            category: category.domain,
            pattern: pattern.domain,
            formality: formality.domain,
            colors: colors,
            visionLabels: labels,
            source: .onDeviceModel
        )
    }
}

extension GeneratedCategory {
    var domain: ClothingCategory {
        switch self {
        case .tops: .tops
        case .bottoms: .bottoms
        case .dresses: .dresses
        case .outerwear: .outerwear
        case .shoes: .shoes
        case .accessories: .accessories
        case .activewear: .activewear
        case .other: .other
        }
    }
}

extension GeneratedFormality {
    var domain: Formality {
        switch self {
        case .casual: .casual
        case .smartCasual: .smartCasual
        case .formal: .formal
        }
    }
}

extension GeneratedPattern {
    var domain: ClothingPattern {
        switch self {
        case .solid: .solid
        case .striped: .striped
        case .checked: .checked
        case .floral: .floral
        case .printed: .printed
        case .other: .other
        case .unknown: .unknown
        }
    }
}
