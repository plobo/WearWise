import Foundation
import Testing
@testable import WearWise

struct ColorHarmonyTests {
    @Test func neutralsPairWell() {
        #expect(ColorHarmony.score(.white, .navy) >= 0.85)
        #expect(ColorHarmony.score(.lightBlue, .beige) >= 0.85)
    }

    @Test func awkwardPairsScoreLow() {
        #expect(ColorHarmony.score(.black, .brown) < 0.5)
        #expect(ColorHarmony.score(.red, .green) < 0.5)
        #expect(ColorHarmony.score(.red, .red) < 0.5)
    }

    @Test func isSymmetric() {
        for a in ClothingColor.allCases {
            for b in ClothingColor.allCases {
                #expect(ColorHarmony.score(a, b) == ColorHarmony.score(b, a))
            }
        }
    }
}

struct OutfitMatcherTests {
    let shirt = makeItem("Light blue oxford", .tops, .lightBlue, .smartCasual)
    let chinos = makeItem("Beige chinos", .bottoms, .beige, .smartCasual)
    let jeans = makeItem("Dark jeans", .bottoms, .navy, .casual)
    let suitTrousers = makeItem("Black suit trousers", .bottoms, .black, .formal)
    let redJoggers = makeItem("Red joggers", .bottoms, .red, .casual)
    let loafers = makeItem("Brown loafers", .shoes, .brown, .smartCasual)
    let sneakers = makeItem("White sneakers", .shoes, .white, .casual)
    let oxfords = makeItem("Black oxfords", .shoes, .black, .formal)
    let runners = makeItem("Green runners", .shoes, .green, .casual)

    var wardrobe: [ClothingItem] { [shirt, chinos, jeans, suitTrousers, redJoggers, loafers, sneakers, oxfords, runners] }

    private func suggestions(_ top: ClothingItem, _ items: [ClothingItem]) -> [OutfitSuggestion] {
        if case .suggestions(let list) = OutfitMatcher.match(top: top, wardrobe: items) { return list }
        Issue.record("Expected suggestions")
        return []
    }

    @Test func bestMatchIsSameDressLevelWithGoodColours() {
        let best = suggestions(shirt, wardrobe).first
        #expect(best?.bottom.id == chinos.id)
        #expect(best?.shoes.id == loafers.id)
        #expect(best?.rating == "Great match")
        #expect(best?.reasons.contains("All smart casual") == true)
    }

    @Test func onlySuggestsOwnedItemsInTheRightRoles() {
        let list = suggestions(shirt, wardrobe)
        let owned = Set(wardrobe.map(\.id))
        #expect(!list.isEmpty)
        for s in list {
            #expect(Set(s.itemIDs).isSubset(of: owned))
            #expect(s.top.id == shirt.id)
            #expect(s.bottom.category == .bottoms)
            #expect(s.shoes.category == .shoes)
            #expect(OutfitMatcher.isValid(s, wardrobe: wardrobe))
        }
    }

    @Test func neverMixesCasualWithFormal() {
        for s in suggestions(shirt, wardrobe) {
            let levels = Set([s.top.formality, s.bottom.formality, s.shoes.formality])
            #expect(!(levels.contains(.casual) && levels.contains(.formal)))
        }
        #expect(OutfitMatcher.evaluate(top: shirt, bottom: suitTrousers, shoes: sneakers) == nil)
    }

    @Test func clashingColoursAreLeftOut() {
        let list = suggestions(shirt, wardrobe)
        #expect(!list.contains { $0.bottom.id == redJoggers.id && $0.shoes.id == runners.id })
    }

    @Test func limitsResultsAndKeepsVariety() {
        let list = suggestions(shirt, wardrobe)
        #expect(list.count <= 5)
        let bottomCounts = Dictionary(grouping: list, by: \.bottom.id).mapValues(\.count)
        let shoeCounts = Dictionary(grouping: list, by: \.shoes.id).mapValues(\.count)
        #expect(bottomCounts.values.allSatisfy { $0 <= 2 })
        #expect(shoeCounts.values.allSatisfy { $0 <= 2 })
        #expect(list.map(\.score) == list.map(\.score).sorted(by: >))
    }

    @Test func reportsMissingPieces() {
        #expect(OutfitMatcher.match(top: shirt, wardrobe: [shirt, chinos]) == .missingPieces(needsBottoms: false, needsShoes: true))
        #expect(OutfitMatcher.match(top: shirt, wardrobe: [shirt]) == .missingPieces(needsBottoms: true, needsShoes: true))
    }

    @Test func reportsNoGoodMatchesWhenEverythingClashes() {
        let pinkTee = makeItem("Pink tee", .tops, .red, .casual)
        let result = OutfitMatcher.match(top: pinkTee, wardrobe: [pinkTee, redJoggers, runners])
        #expect(result == .noGoodMatches)
    }

    @Test func isDeterministic() {
        #expect(suggestions(shirt, wardrobe) == suggestions(shirt, wardrobe))
    }

    @Test func validationRejectsUnknownOrMisassignedItems() {
        let stranger = makeItem("Borrowed boots", .shoes, .black, .casual)
        let fake = OutfitSuggestion(top: shirt, bottom: chinos, shoes: stranger, score: 1, reasons: [])
        #expect(!OutfitMatcher.isValid(fake, wardrobe: wardrobe))
        let swapped = OutfitSuggestion(top: shirt, bottom: loafers, shoes: chinos, score: 1, reasons: [])
        #expect(!OutfitMatcher.isValid(swapped, wardrobe: wardrobe))
    }
}
