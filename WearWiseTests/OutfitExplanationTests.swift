import Foundation
import Testing
@testable import WearWise

private let shirt = makeItem("Light blue oxford", .tops, .lightBlue, .smartCasual)
private let chinos = makeItem("Beige chinos", .bottoms, .beige, .smartCasual)
private let loafers = makeItem("Brown loafers", .shoes, .brown, .smartCasual)
private let jeans = makeItem("Dark jeans", .bottoms, .navy, .casual)

private func suggestion() -> OutfitSuggestion {
    OutfitMatcher.evaluate(top: shirt, bottom: chinos, shoes: loafers)!
}

// MARK: - Validator

struct OutfitExplanationValidatorTests {
    let input = OutfitExplanationInput(suggestion())
    let others = ["Dark jeans", "White sneakers"]

    private func check(_ text: String) -> String? {
        OutfitExplanationValidator.validated(text, for: input, otherItemNames: others)
    }

    @Test func acceptsExplanationThatUsesOnlyOutfitPieces() {
        let text = "The beige chinos and brown loafers give your light blue oxford a warm, relaxed polish that's perfect for smart casual days."
        #expect(check(text) == text)
    }

    @Test func acceptsGenericRoleWords() {
        #expect(check("Neutral pants and shoes let your shirt stand out") == "Neutral pants and shoes let your shirt stand out.")
    }

    @Test func cleansQuotesWhitespaceAndAddsFullStop() {
        #expect(check("  \"Easy  neutrals\nwith a crisp top\"  ") == "Easy neutrals with a crisp top.")
    }

    @Test(arguments: [
        "Finish it with a navy blazer for evenings.",
        "A brown belt ties the loafers to the chinos.",
        "These look great with white sneakers too.",
        "Swap the chinos for jeans on weekends.",
        "Consider adding a watch.",
        "The soft cotton oxford feels relaxed.",
        "Leather loafers elevate the look.",
        "A smart look for under $50.",
        "Your dark jeans would also work here.",
    ])
    func rejectsInventedClothesMaterialsAndChanges(_ text: String) {
        #expect(check(text) == nil)
    }

    @Test func rejectsEmptyAndOverlongText() {
        #expect(check("   ") == nil)
        #expect(check(String(repeating: "Lovely. ", count: 50)) == nil)
    }

    @Test func materialAllowedWhenItIsInTheItemName() {
        let denimShirt = makeItem("Denim shirt", .tops, .blue, .casual)
        let input = OutfitExplanationInput(OutfitMatcher.evaluate(top: denimShirt, bottom: chinos, shoes: loafers)!)
        let text = "The denim shirt relaxes the beige chinos."
        #expect(OutfitExplanationValidator.validated(text, for: input, otherItemNames: []) == text)
    }

    @Test func pluralsMatchSingulars() {
        #expect(OutfitExplanationValidator.words(in: "Loafers, chinos and dress") == ["loafer", "chino", "and", "dress"])
    }
}

// MARK: - Prompt

struct OutfitExplanationPromptTests {
    @Test func promptListsOnlyOutfitPiecesAndFacts() {
        let prompt = FoundationModelsOutfitExplainer.prompt(for: OutfitExplanationInput(suggestion()))
        #expect(prompt.contains("- Top: Light blue oxford (light blue, smart casual)"))
        #expect(prompt.contains("- Pants: Beige chinos (beige, smart casual)"))
        #expect(prompt.contains("- Shoes: Brown loafers (brown, smart casual)"))
        #expect(prompt.contains("Facts: Beige pants keep the light blue top in focus."))
        #expect(!prompt.contains("jeans"))
    }
}

// MARK: - Provider

/// Fake model: returns fixed text and records how many requests ran at once.
final class FakeExplainer: OutfitExplaining, @unchecked Sendable {
    private let lock = NSLock()
    private var running = 0
    private var _maxConcurrent = 0
    private var _calls = 0
    let reply: @Sendable (OutfitExplanationInput) throws -> String

    init(reply: @escaping @Sendable (OutfitExplanationInput) throws -> String) { self.reply = reply }

    var maxConcurrent: Int { lock.withLock { _maxConcurrent } }
    var calls: Int { lock.withLock { _calls } }

    func explain(_ input: OutfitExplanationInput) async throws -> String {
        lock.withLock { running += 1; _calls += 1; _maxConcurrent = max(_maxConcurrent, running) }
        try? await Task.sleep(for: .milliseconds(30))
        lock.withLock { running -= 1 }
        return try reply(input)
    }
}

@MainActor
struct OutfitExplanationProviderTests {
    let wardrobe = [shirt, chinos, loafers, jeans]

    @Test func validTextIsShownAndCached() async {
        let fake = FakeExplainer { _ in "Warm neutrals make your light blue oxford the star." }
        let provider = OutfitExplanationProvider(explainer: fake, availabilityProvider: { .available })
        let s = suggestion()

        await provider.request(s, wardrobe: wardrobe)
        await provider.request(s, wardrobe: wardrobe)

        #expect(provider.state(for: s) == .ready("Warm neutrals make your light blue oxford the star."))
        #expect(fake.calls == 1)
    }

    @Test func rejectedTextFallsBackToRules() async {
        let fake = FakeExplainer { _ in "Add a navy blazer and your dark jeans." }
        let provider = OutfitExplanationProvider(explainer: fake, availabilityProvider: { .available })
        await provider.request(suggestion(), wardrobe: wardrobe)
        #expect(provider.state(for: suggestion()) == .fallback)
    }

    @Test func modelErrorFallsBackToRules() async {
        let fake = FakeExplainer { _ in throw AIError.generationFailed }
        let provider = OutfitExplanationProvider(explainer: fake, availabilityProvider: { .available })
        await provider.request(suggestion(), wardrobe: wardrobe)
        #expect(provider.state(for: suggestion()) == .fallback)
    }

    @Test func unavailableModelIsNeverCalled() async {
        let fake = FakeExplainer { _ in "Should not be used." }
        let provider = OutfitExplanationProvider(explainer: fake, availabilityProvider: { .deviceNotEligible })
        await provider.request(suggestion(), wardrobe: wardrobe)
        #expect(provider.state(for: suggestion()) == .fallback)
        #expect(fake.calls == 0)
    }

    @Test func requestsRunOneAtATime() async {
        let fake = FakeExplainer { input in "Nice with the \(input.pieces[1].name.lowercased())." }
        let provider = OutfitExplanationProvider(explainer: fake, availabilityProvider: { .available })
        let first = suggestion()
        let second = OutfitMatcher.evaluate(top: shirt, bottom: jeans, shoes: loafers)!

        async let a: Void = provider.request(first, wardrobe: wardrobe)
        async let b: Void = provider.request(second, wardrobe: wardrobe)
        _ = await (a, b)

        #expect(fake.maxConcurrent == 1)
        #expect(provider.state(for: first) == .ready("Nice with the beige chinos."))
        #expect(provider.state(for: second) == .ready("Nice with the dark jeans."))
    }

    @Test func changedItemDetailsGetANewExplanation() async {
        let fake = FakeExplainer { _ in "Easy neutrals." }
        let provider = OutfitExplanationProvider(explainer: fake, availabilityProvider: { .available })
        await provider.request(suggestion(), wardrobe: wardrobe)

        var renamed = chinos
        renamed.name = "Stone chinos"
        let updated = OutfitMatcher.evaluate(top: shirt, bottom: renamed, shoes: loafers)!
        await provider.request(updated, wardrobe: wardrobe)
        #expect(fake.calls == 2)
    }
}

// MARK: - Live model (opt-in)

/// Calls the real on-device model. Opt in with WEARWISE_LIVE_AI=1 on a device with Apple Intelligence.
struct LiveOutfitExplainerTests {
    static var enabled: Bool { ProcessInfo.processInfo.environment["WEARWISE_LIVE_AI"] == "1" }

    @Test(.enabled(if: enabled, "Set WEARWISE_LIVE_AI=1 to call the on-device model"), .timeLimit(.minutes(1)))
    func liveExplanationPassesValidation() async throws {
        let input = OutfitExplanationInput(suggestion())
        let text = try await FoundationModelsOutfitExplainer().explain(input)
        let validated = OutfitExplanationValidator.validated(text, for: input, otherItemNames: ["Dark jeans", "White sneakers"])
        #expect(validated != nil, "Model wrote: \(text)")
    }
}
