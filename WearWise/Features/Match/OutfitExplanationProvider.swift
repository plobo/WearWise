import Foundation
import Observation

/// Requests AI explanations one at a time, validates them, and remembers them for the session.
@MainActor
@Observable
final class OutfitExplanationProvider {
    enum State: Equatable {
        case pending
        /// Validated AI text.
        case ready(String)
        /// AI unavailable, failed, or its text was rejected: show the rule-based reasons.
        case fallback
    }

    private(set) var states: [OutfitExplanationInput: State] = [:]

    private let explainer: any OutfitExplaining
    private let availabilityProvider: @MainActor () -> AIAvailability
    /// The most recent queued request, so generations run strictly one after another.
    @ObservationIgnored private var tail: Task<Void, Never>?

    init(
        explainer: any OutfitExplaining = FoundationModelsOutfitExplainer(),
        availabilityProvider: @escaping @MainActor () -> AIAvailability = { AIAvailabilityChecker.current() }
    ) {
        self.explainer = explainer
        self.availabilityProvider = availabilityProvider
    }

    func state(for suggestion: OutfitSuggestion) -> State? {
        states[OutfitExplanationInput(suggestion)]
    }

    /// Asks for an explanation unless one is already known or in progress.
    func request(_ suggestion: OutfitSuggestion, wardrobe: [ClothingItem]) async {
        let input = OutfitExplanationInput(suggestion)
        guard states[input] == nil else { return }
        guard availabilityProvider().isAvailable else {
            states[input] = .fallback
            return
        }
        states[input] = .pending

        let previous = tail
        let explainer = self.explainer
        let job = Task<String?, Never> {
            await previous?.value
            return try? await explainer.explain(input)
        }
        tail = Task { _ = await job.value }

        let otherNames = wardrobe.filter { !suggestion.itemIDs.contains($0.id) }.map(\.name)
        if let raw = await job.value,
           let text = OutfitExplanationValidator.validated(raw, for: input, otherItemNames: otherNames) {
            states[input] = .ready(text)
        } else {
            states[input] = .fallback
        }
    }
}
