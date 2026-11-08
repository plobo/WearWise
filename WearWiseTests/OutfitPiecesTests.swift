import Foundation
import SwiftData
import Testing
@testable import WearWise

private let shirt = makeItem("Light blue oxford", .tops, .lightBlue, .smartCasual)
private let chinos = makeItem("Beige chinos", .bottoms, .beige, .smartCasual)
private let loafers = makeItem("Brown loafers", .shoes, .brown, .smartCasual)
private let sneakers = makeItem("White sneakers", .shoes, .white, .casual)
private let blazer = makeItem("Navy blazer", .outerwear, .navy, .smartCasual)
private let parka = makeItem("Orange parka", .outerwear, .orange, .casual)
private let tuxJacket = makeItem("Black tux jacket", .outerwear, .black, .formal)
private let dress = makeItem("Burgundy dress", .dresses, .burgundy, .smartCasual)
private let heels = makeItem("Black heels", .shoes, .black, .formal)

// MARK: - Dresses

struct DressMatchingTests {
    private func suggestions(_ base: ClothingItem, _ wardrobe: [ClothingItem]) -> [OutfitSuggestion] {
        if case .suggestions(let list) = OutfitMatcher.match(top: base, wardrobe: wardrobe) { return list }
        return []
    }

    @Test func dressNeedsOnlyShoes() {
        let list = suggestions(dress, [dress, loafers, heels])
        #expect(!list.isEmpty)
        #expect(list.allSatisfy { $0.bottom == nil && $0.isDressOutfit })
        #expect(list.first?.title == "Burgundy dress + Brown loafers" || list.first?.title == "Burgundy dress + Black heels")
    }

    @Test func dressIgnoresPants() {
        let list = suggestions(dress, [dress, chinos, loafers])
        #expect(list.allSatisfy { $0.bottom == nil })
    }

    @Test func dressWithoutShoesAsksOnlyForShoes() {
        #expect(OutfitMatcher.match(top: dress, wardrobe: [dress, chinos]) == .missingPieces(needsBottoms: false, needsShoes: true))
    }

    @Test func dressReasonsMentionTheDress() {
        let s = OutfitMatcher.evaluate(top: dress, bottom: nil, shoes: loafers)
        #expect(s?.reasons.first == "Brown shoes let the burgundy dress lead")
        #expect(s?.reasons.last == "All smart casual")
    }

    @Test func validationRequiresNoPantsForDressesAndPantsForTops() {
        let dressWithPants = OutfitSuggestion(top: dress, bottom: chinos, shoes: loafers, score: 1, reasons: [])
        #expect(!OutfitMatcher.isValid(dressWithPants, wardrobe: [dress, chinos, loafers]))
        let topWithoutPants = OutfitSuggestion(top: shirt, bottom: nil, shoes: loafers, score: 1, reasons: [])
        #expect(!OutfitMatcher.isValid(topWithoutPants, wardrobe: [shirt, loafers]))
    }

    @Test func otherCategoriesCannotStartAnOutfit() {
        #expect(OutfitMatcher.match(top: blazer, wardrobe: [blazer, chinos, loafers]) == .noGoodMatches)
    }
}

// MARK: - Optional layer

struct LayerSelectionTests {
    private func first(_ wardrobe: [ClothingItem]) -> OutfitSuggestion? {
        if case .suggestions(let list) = OutfitMatcher.match(top: shirt, wardrobe: wardrobe) { return list.first }
        return nil
    }

    @Test func addsMatchingLayerWithReason() {
        let s = first([shirt, chinos, loafers, blazer])
        #expect(s?.layer?.id == blazer.id)
        #expect(s?.reasons.last == "The navy blazer works over it when it's cooler")
    }

    @Test func layerNeverChangesScoreOrOrder() {
        let without = first([shirt, chinos, loafers, sneakers])
        let with = first([shirt, chinos, loafers, sneakers, blazer])
        #expect(without?.key == with?.key)
        #expect(without?.score == with?.score)
    }

    @Test func skipsLayersThatClashOrAreTooFormal() {
        // The formal tux jacket is two steps from casual sneakers; orange vs light blue isn't a listed pairing.
        #expect(OutfitMatcher.bestLayer(for: OutfitMatcher.evaluate(top: shirt, bottom: chinos, shoes: sneakers)!, in: [tuxJacket]) == nil)
        #expect(OutfitMatcher.bestLayer(for: OutfitMatcher.evaluate(top: shirt, bottom: chinos, shoes: loafers)!, in: [parka]) == nil)
    }

    @Test func noOuterwearMeansNoLayer() {
        #expect(first([shirt, chinos, loafers])?.layer == nil)
    }

    @Test func layerMustBeOwnedOuterwear() {
        var s = OutfitMatcher.evaluate(top: shirt, bottom: chinos, shoes: loafers)!
        s.layer = blazer
        #expect(OutfitMatcher.isValid(s, wardrobe: [shirt, chinos, loafers, blazer]))
        #expect(!OutfitMatcher.isValid(s, wardrobe: [shirt, chinos, loafers]), "Layer not owned")
        s.layer = sneakers
        #expect(!OutfitMatcher.isValid(s, wardrobe: [shirt, chinos, loafers, sneakers]), "Layer must be outerwear")
    }

    @Test func dressesGetLayersToo() {
        if case .suggestions(let list) = OutfitMatcher.match(top: dress, wardrobe: [dress, loafers, blazer]) {
            #expect(list.first?.layer?.id == blazer.id)
        } else {
            Issue.record("Expected suggestions")
        }
    }
}

// MARK: - Explanations with layers and dresses

struct LayerExplanationTests {
    private func input(_ s: OutfitSuggestion) -> OutfitExplanationInput { OutfitExplanationInput(s) }

    @Test func layerCanBeMentionedWhenSuggested() {
        var s = OutfitMatcher.evaluate(top: shirt, bottom: chinos, shoes: loafers)!
        s.layer = blazer
        let text = "Beige chinos and brown loafers suit your light blue oxford; add the navy blazer as a layer when it's cooler."
        #expect(OutfitExplanationValidator.validated(text, for: input(s), otherItemNames: []) == text)
    }

    @Test(arguments: [
        "The brown loafers suit your light blue oxford perfectly.",
        "Beige chinos tie the whole look together.",
        "Short on time? This one is easy.",
    ])
    func commonStylingVerbsAreNotMistakenForClothes(_ text: String) {
        let s = OutfitMatcher.evaluate(top: shirt, bottom: chinos, shoes: loafers)!
        #expect(OutfitExplanationValidator.validated(text, for: input(s), otherItemNames: []) == text)
    }

    @Test func layerTalkRejectedWithoutALayer() {
        let s = OutfitMatcher.evaluate(top: shirt, bottom: chinos, shoes: loafers)!
        #expect(OutfitExplanationValidator.validated("Layer a jacket over it.", for: input(s), otherItemNames: []) == nil)
    }

    @Test func dressOutfitPromptHasNoPants() {
        let prompt = FoundationModelsOutfitExplainer.prompt(for: input(OutfitMatcher.evaluate(top: dress, bottom: nil, shoes: loafers)!))
        #expect(prompt.contains("- Dress: Burgundy dress"))
        #expect(!prompt.contains("Pants"))
    }

    @Test func dressWordAllowedOnlyForDressOutfits() {
        let dressInput = input(OutfitMatcher.evaluate(top: dress, bottom: nil, shoes: loafers)!)
        #expect(OutfitExplanationValidator.validated("The dress shines with brown shoes.", for: dressInput, otherItemNames: []) != nil)
        let topInput = input(OutfitMatcher.evaluate(top: shirt, bottom: chinos, shoes: loafers)!)
        #expect(OutfitExplanationValidator.validated("Like a dress, it flows.", for: topInput, otherItemNames: []) == nil)
    }
}

// MARK: - Storage

@MainActor
struct OutfitLayerStorageTests {
    @Test func savedOutfitRemembersLayerAndDressOutfitsPersist() throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let store = OutfitStore(repository: SwiftDataOutfitRepository(container: container))
        let dressKey = OutfitKey(topID: dress.id, bottomID: nil, shoesID: loafers.id)
        try store.toggleSaved(dressKey, extras: OutfitExtras(layerID: blazer.id))

        let reopened = OutfitStore(repository: SwiftDataOutfitRepository(container: container))
        let outfit = try #require(reopened.outfit(for: dressKey))
        #expect(outfit.layerID == blazer.id)
        #expect(outfit.key.bottomID == nil)

        let resolved = try #require(ResolvedOutfit(outfit, wardrobe: [dress, loafers, blazer]))
        #expect(resolved.title == "Burgundy dress + Brown loafers")
        #expect(resolved.pieces.map(\.id) == [dress.id, loafers.id, blazer.id])
    }

    @Test func missingLayerIsDroppedButOutfitStays() {
        let outfit = Outfit(id: UUID(), key: OutfitKey(topID: shirt.id, bottomID: chinos.id, shoesID: loafers.id),
                            layerID: blazer.id, isSaved: true, isHidden: false, wornDates: [], dateCreated: .now)
        let resolved = ResolvedOutfit(outfit, wardrobe: [shirt, chinos, loafers])
        #expect(resolved != nil)
        #expect(resolved?.layer == nil)
    }

    @Test func deletingJacketKeepsOutfitButClearsLayer() throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let store = OutfitStore(repository: SwiftDataOutfitRepository(container: container))
        let key = OutfitKey(topID: shirt.id, bottomID: chinos.id, shoesID: loafers.id)
        try store.toggleSaved(key, extras: OutfitExtras(layerID: blazer.id))

        try store.removeOutfits(containing: blazer.id)
        #expect(store.outfit(for: key)?.layerID == nil)
        store.reload()
        #expect(store.outfit(for: key)?.isSaved == true)
        #expect(store.outfit(for: key)?.layerID == nil)
    }

    @Test func migratesVersion3OutfitsToVersion4() throws {
        let dir = tempDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "wardrobe.store")
        let outfit = Outfit(id: UUID(), key: OutfitKey(topID: shirt.id, bottomID: chinos.id, shoesID: loafers.id),
                            isSaved: true, isHidden: false, wornDates: [referenceNoon], dateCreated: referenceNoon)

        do {
            let v3Schema = Schema(versionedSchema: WardrobeSchemaV3.self)
            let v3 = try ModelContainer(for: v3Schema, configurations: ModelConfiguration(schema: v3Schema, url: url))
            v3.mainContext.insert(WardrobeSchemaV3.ClothingItemRecord(item: shirt))
            v3.mainContext.insert(WardrobeSchemaV3.OutfitRecord(outfit: outfit))
            try v3.mainContext.save()
        }

        let container = try ModelContainerFactory.make(storeURL: url)
        let migrated = try SwiftDataOutfitRepository(container: container).allOutfits()
        #expect(migrated == [outfit])
        #expect(migrated.first?.layerID == nil)
        #expect(try SwiftDataClothingRepository(container: container).allItems().map(\.id) == [shirt.id])
    }
}
