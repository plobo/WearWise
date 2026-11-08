import Foundation
import SwiftData
import Testing
@testable import WearWise

private func accessory(_ name: String, _ color: ClothingColor, _ formality: Formality = .smartCasual, kind: AccessoryKind? = nil) -> ClothingItem {
    var item = makeItem(name, .accessories, color, formality)
    item.accessoryKind = kind
    return item
}

private let shirt = makeItem("Light blue oxford", .tops, .lightBlue, .smartCasual)
private let chinos = makeItem("Beige chinos", .bottoms, .beige, .smartCasual)
private let loafers = makeItem("Brown loafers", .shoes, .brown, .smartCasual)
private let oxfords = makeItem("Black oxfords", .shoes, .black, .smartCasual)
private let sneakers = makeItem("White sneakers", .shoes, .white, .casual)
private let jeans = makeItem("Dark jeans", .bottoms, .navy, .casual)
private let dress = makeItem("Burgundy dress", .dresses, .burgundy, .smartCasual)
private let brownBelt = accessory("Brown belt", .brown)
private let blackBelt = accessory("Black belt", .black)
private let navyScarf = accessory("Navy scarf", .navy)
private let redHat = accessory("Red hat", .red)

// MARK: - Kind inference

struct AccessoryKindTests {
    @Test(arguments: [
        ("Brown leather belt", AccessoryKind.belt),
        ("Tan tote", .bag),
        ("Grey wool scarf", .scarf),
        ("Navy baseball cap", .hat),
        ("Silver watch", .watch),
        ("Gold earrings", .jewelry),
    ])
    func infersFromName(name: String, expected: AccessoryKind) {
        #expect(AccessoryKind.infer(from: [name]) == expected)
    }

    @Test func unknownNamesInferNothing() {
        #expect(AccessoryKind.infer(from: ["Lucky charm"]) == nil)
        #expect(accessory("Lucky charm", .black).resolvedAccessoryKind == .other)
    }

    @Test func savedKindWinsOverName() {
        #expect(accessory("Brown belt", .brown, kind: .bag).resolvedAccessoryKind == .bag)
    }

    @Test func nonAccessoriesHaveNoKind() {
        #expect(shirt.resolvedAccessoryKind == nil)
    }

    @Test func draftKeepsKindOnlyForAccessories() {
        var draft = completeDraft()
        draft.accessoryKind = .belt
        #expect(draft.normalizedAccessoryKind == nil)
        draft.category = .accessories
        #expect(draft.normalizedAccessoryKind == .belt)
    }

    @Test func analysisLabelsSuggestKind() {
        let analysis = ClothingAnalysis(
            name: "Brown accessory", category: .accessories, pattern: .solid, formality: .smartCasual,
            colors: [ColorShare(color: .brown, share: 1)], visionLabels: [VisionLabel(identifier: "belt", confidence: 0.7)],
            source: .visionOnly(reason: "test")
        )
        #expect(ClothingDraft(analysis: analysis).accessoryKind == .belt)
    }
}

// MARK: - Belt and accessory rules

struct AccessoryMatchingTests {
    private func first(_ top: ClothingItem, _ wardrobe: [ClothingItem]) -> OutfitSuggestion? {
        if case .suggestions(let list) = OutfitMatcher.match(top: top, wardrobe: wardrobe) { return list.first }
        return nil
    }

    @Test func beltMatchesTheShoes() {
        let s = first(shirt, [shirt, chinos, loafers, brownBelt, blackBelt])
        #expect(s?.accessories.map(\.id) == [brownBelt.id])
        #expect(s?.extraReasons.contains("The brown belt matches your brown loafers") == true)
    }

    @Test func noBeltWhenOnlyAClashingBeltExists() {
        let s = OutfitMatcher.evaluate(top: shirt, bottom: chinos, shoes: loafers)!
        #expect(OutfitMatcher.bestBelt(for: s, in: [blackBelt]) == nil, "Black belt with brown shoes")
    }

    @Test func sneakersAllowANeutralBeltThatSuitsThePants() {
        let s = OutfitMatcher.evaluate(top: shirt, bottom: jeans, shoes: sneakers)!
        let result = OutfitMatcher.bestBelt(for: s, in: [brownBelt])
        #expect(result?.belt.id == brownBelt.id)
        #expect(result?.matchesShoes == false)
    }

    @Test func dressesNeverGetABelt() {
        let s = OutfitMatcher.evaluate(top: dress, bottom: nil, shoes: loafers)!
        #expect(OutfitMatcher.bestBelt(for: s, in: [brownBelt]) == nil)
    }

    @Test func oneOtherAccessoryWhenColoursWork() {
        let s = first(shirt, [shirt, chinos, loafers, navyScarf, redHat])
        #expect(s?.accessories.map(\.id) == [navyScarf.id], "Red hat clashes with light blue")
        #expect(s?.extraReasons.last == "The navy scarf finishes the look")
    }

    @Test func atMostABeltAndOneOther() {
        let watch = accessory("Brown watch", .brown)
        let s = first(shirt, [shirt, chinos, loafers, brownBelt, navyScarf, watch])
        #expect(s?.accessories.count == 2)
        #expect(s?.accessories.first?.id == brownBelt.id)
    }

    @Test func extrasNeverChangeScoreOrOrder() {
        let core = [shirt, chinos, jeans, loafers, oxfords]
        let plain = OutfitMatcher.match(top: shirt, wardrobe: core)
        let extras = OutfitMatcher.match(top: shirt, wardrobe: core + [brownBelt, blackBelt, navyScarf])
        guard case .suggestions(let a) = plain, case .suggestions(let b) = extras else {
            Issue.record("Expected suggestions")
            return
        }
        #expect(a.map(\.key) == b.map(\.key))
        #expect(a.map(\.score) == b.map(\.score))
    }

    @Test func validationRejectsUnownedOrMisplacedAccessories() {
        var s = OutfitMatcher.evaluate(top: shirt, bottom: chinos, shoes: loafers)!
        s.accessories = [brownBelt]
        #expect(OutfitMatcher.isValid(s, wardrobe: [shirt, chinos, loafers, brownBelt]))
        #expect(!OutfitMatcher.isValid(s, wardrobe: [shirt, chinos, loafers]), "Not owned")
        s.accessories = [chinos]
        #expect(!OutfitMatcher.isValid(s, wardrobe: [shirt, chinos, loafers]), "Core piece reused as accessory")

        var dressOutfit = OutfitMatcher.evaluate(top: dress, bottom: nil, shoes: loafers)!
        dressOutfit.accessories = [brownBelt]
        #expect(!OutfitMatcher.isValid(dressOutfit, wardrobe: [dress, loafers, brownBelt]), "No belt without pants")
    }
}

// MARK: - Explanations

struct AccessoryExplanationTests {
    @Test func optionalBeltCanBeMentioned() {
        var s = OutfitMatcher.evaluate(top: shirt, bottom: chinos, shoes: loafers)!
        s.accessories = [accessory("Tan strap", .brown, kind: .belt)]
        let input = OutfitExplanationInput(s)
        #expect(input.pieces.last?.role == "Optional belt")
        let text = "A belt in tan echoes the brown loafers."
        #expect(OutfitExplanationValidator.validated(text, for: input, otherItemNames: []) == text)
    }

    @Test func beltTalkRejectedWhenNoBeltSuggested() {
        let input = OutfitExplanationInput(OutfitMatcher.evaluate(top: shirt, bottom: chinos, shoes: loafers)!)
        #expect(OutfitExplanationValidator.validated("A brown belt ties it up.", for: input, otherItemNames: []) == nil)
    }
}

// MARK: - Storage

@MainActor
struct AccessoryStorageTests {
    @Test func savedOutfitKeepsAccessoriesAndDropsDeletedOnes() throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let store = OutfitStore(repository: SwiftDataOutfitRepository(container: container))
        let key = OutfitKey(topID: shirt.id, bottomID: chinos.id, shoesID: loafers.id)
        try store.toggleSaved(key, extras: OutfitExtras(accessoryIDs: [brownBelt.id, navyScarf.id]))

        let saved = try #require(store.outfit(for: key))
        let resolved = try #require(ResolvedOutfit(saved, wardrobe: [shirt, chinos, loafers, brownBelt, navyScarf]))
        #expect(resolved.extras.map(\.id) == [brownBelt.id, navyScarf.id])

        try store.removeOutfits(containing: brownBelt.id)
        store.reload()
        #expect(store.outfit(for: key)?.accessoryIDs == [navyScarf.id])
        #expect(store.outfit(for: key)?.isSaved == true)
    }

    @Test func accessoryKindPersists() throws {
        let repo = SwiftDataClothingRepository(container: try ModelContainerFactory.make(inMemory: true))
        let belt = accessory("Tan strap", .brown, kind: .belt)
        try repo.insert(belt)
        #expect(try repo.allItems().first?.accessoryKind == .belt)
    }

    @Test func migratesVersion4StoreToVersion5() throws {
        let dir = tempDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "wardrobe.store")
        let outfit = Outfit(id: UUID(), key: OutfitKey(topID: dress.id, bottomID: nil, shoesID: loafers.id),
                            layerID: UUID(), isSaved: true, isHidden: false, wornDates: [], dateCreated: referenceNoon)

        do {
            let v4Schema = Schema(versionedSchema: WardrobeSchemaV4.self)
            let v4 = try ModelContainer(for: v4Schema, configurations: ModelConfiguration(schema: v4Schema, url: url))
            v4.mainContext.insert(WardrobeSchemaV4.ClothingItemRecord(item: brownBelt))
            v4.mainContext.insert(WardrobeSchemaV4.OutfitRecord(outfit: outfit))
            try v4.mainContext.save()
        }

        let container = try ModelContainerFactory.make(storeURL: url)
        let items = try SwiftDataClothingRepository(container: container).allItems()
        #expect(items.first?.accessoryKind == nil)
        #expect(items.first?.resolvedAccessoryKind == .belt, "Older accessories are typed from their name")
        let migrated = try SwiftDataOutfitRepository(container: container).allOutfits()
        #expect(migrated == [outfit])
        #expect(migrated.first?.accessoryIDs == [])
    }
}
