import Foundation
import FoundationModels

/// Writes a short explanation for an outfit the app has already chosen.
protocol OutfitExplaining: Sendable {
    func explain(_ input: OutfitExplanationInput) async throws -> String
}

@Generable(description: "A short explanation of why an outfit works")
struct GeneratedOutfitExplanation {
    @Guide(description: "One or two sentences, at most 40 words, speaking to the wearer as 'you'. Mention only the listed items.")
    var text: String
}

/// On-device Foundation Models implementation. Text in, text out: the model never chooses clothes.
struct FoundationModelsOutfitExplainer: OutfitExplaining {
    static let instructions = """
    You are a concise personal stylist inside a wardrobe app.
    The app has already chosen an outfit from the user's own clothes. Explain why it works.
    Use only the facts provided. Refer only to the listed items, by name or by their role.
    Items marked "Optional" are extras: a layer to wear over the outfit when it's cooler, or an accessory to finish it.
    Never suggest any other clothing, and never suggest swapping pieces.
    Never mention brands, materials, fabrics, prices, sizes or fit.
    Write one or two warm, specific sentences, at most 40 words. No emojis, no lists.
    """

    func explain(_ input: OutfitExplanationInput) async throws -> String {
        let availability = AIAvailabilityChecker.current()
        guard availability.isAvailable else { throw AIError.unavailable(availability) }

        let session = LanguageModelSession(instructions: Self.instructions)
        do {
            let response = try await session.respond(
                to: Self.prompt(for: input),
                generating: GeneratedOutfitExplanation.self,
                options: GenerationOptions(sampling: .greedy)
            )
            return response.content.text
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as LanguageModelSession.GenerationError {
            throw FoundationModelsClothingInterpreter.map(error)
        } catch {
            throw AIError.generationFailed
        }
    }

    static func prompt(for input: OutfitExplanationInput) -> String {
        let pieces = input.pieces.map { piece in
            "- \(piece.role): \(piece.name) (\(piece.color.displayName.lowercased()), \(piece.formality.displayName.lowercased()))"
        }
        return """
        Outfit:
        \(pieces.joined(separator: "\n"))
        Facts: \(input.factsText)
        Explain why this outfit works.
        """
    }
}
