import Foundation
import Testing
@testable import WearWise

struct WardrobeInsightsTests {
    private let longAgo = referenceNoon.addingTimeInterval(-60 * 86_400)

    private func item(_ name: String, _ category: ClothingCategory, _ color: ClothingColor, _ formality: Formality = .smartCasual) -> ClothingItem {
        makeItem(name, category, color, formality, added: longAgo)
    }

    private func outfit(_ top: ClothingItem, _ bottom: ClothingItem?, _ shoes: ClothingItem, worn days: [Int], extras: [UUID] = []) -> Outfit {
        Outfit(
            id: UUID(), key: OutfitKey(topID: top.id, bottomID: bottom?.id, shoesID: shoes.id),
            accessoryIDs: extras, isSaved: false, isHidden: false,
            wornDates: days.map { referenceNoon.addingTimeInterval(TimeInterval(-$0) * 86_400) }.sorted(),
            dateCreated: longAgo
        )
    }

    private func compute(_ items: [ClothingItem], _ outfits: [Outfit] = []) -> WardrobeInsights {
        WardrobeInsights.compute(items: items, outfits: outfits, now: referenceNoon, calendar: utcCalendar)
    }

    @Test func countsCategoriesAndColours() {
        let items = [
            item("White tee", .tops, .white), item("White shirt", .tops, .white), item("Navy chinos", .bottoms, .navy),
            item("Brown loafers", .shoes, .brown),
        ]
        let insights = compute(items)
        #expect(insights.totalItems == 4)
        #expect(insights.categories.first == .init(category: .tops, count: 2))
        #expect(insights.colors.first == .init(color: .white, count: 2, share: 0.5))
    }

    @Test func versatilityCountsTopsEachPieceGoesWith() {
        let shirt = item("Light blue oxford", .tops, .lightBlue)
        let tee = item("White tee", .tops, .white)
        let dress = item("Burgundy dress", .dresses, .burgundy)
        let chinos = item("Beige chinos", .bottoms, .beige)
        let loafers = item("Brown loafers", .shoes, .brown)
        let redRunners = item("Red runners", .shoes, .red, .casual)

        let insights = compute([shirt, tee, dress, chinos, loafers, redRunners])
        let loafersEntry = insights.versatile.first { $0.item.id == loafers.id }
        #expect(loafersEntry?.matchingStarts == 3, "Shirt, tee and dress")
        #expect(loafersEntry?.totalStarts == 3)
        #expect(insights.versatile.first?.item.id == loafers.id)
        #expect(!insights.versatile.contains { $0.item.id == redRunners.id && $0.matchingStarts == 3 })
    }

    @Test func gapsExplainWhyNothingMatches() {
        let gown = item("Black gown", .dresses, .black, .formal)
        let tee = item("White tee", .tops, .white, .casual)
        let sneakers = item("White sneakers", .shoes, .white, .casual)
        let jeans = item("Dark jeans", .bottoms, .navy, .casual)
        let pinkShirt = item("Pink shirt", .tops, .pink, .casual)
        let redJoggers = item("Red joggers", .bottoms, .red, .casual)
        let orangeRunners = item("Orange runners", .shoes, .orange, .casual)

        let insights = compute([gown, tee, sneakers, jeans])
        #expect(insights.needsMatch == [.init(item: gown, reason: "None of your shoes suit its formal style")])

        let colourGap = compute([pinkShirt, redJoggers, orangeRunners])
        #expect(colourGap.needsMatch == [.init(item: pinkShirt, reason: "Its pink doesn't go with your pants and shoes")])

        let missing = compute([tee])
        #expect(missing.needsMatch == [.init(item: tee, reason: "Add pants and shoes to match it")])
    }

    @Test func wearHistoryCountsOnlyCorePieces() {
        let shirt = item("Shirt", .tops, .white)
        let chinos = item("Chinos", .bottoms, .beige)
        let loafers = item("Loafers", .shoes, .brown)
        let belt = item("Belt", .accessories, .brown)
        let insights = compute([shirt, chinos, loafers, belt], [outfit(shirt, chinos, loafers, worn: [0, 3], extras: [belt.id])])

        #expect(insights.hasWearHistory)
        #expect(Set(insights.mostWorn.map(\.item.id)) == [shirt.id, chinos.id, loafers.id])
        #expect(insights.mostWorn.allSatisfy { $0.timesWorn == 2 })
        #expect(!insights.mostWorn.contains { $0.item.id == belt.id })
    }

    @Test func notWornLatelyNeedsHistoryAndSkipsNewItems() {
        let shirt = item("Shirt", .tops, .white)
        let chinos = item("Chinos", .bottoms, .beige)
        let loafers = item("Loafers", .shoes, .brown)
        let oldJeans = item("Old jeans", .bottoms, .navy)
        let newJeans = makeItem("New jeans", .bottoms, .navy, .smartCasual, added: referenceNoon.addingTimeInterval(-3 * 86_400))
        let items = [shirt, chinos, loafers, oldJeans, newJeans]

        #expect(compute(items).notWornLately.isEmpty, "Nothing to say before any wear is logged")

        let insights = compute(items, [
            outfit(shirt, chinos, loafers, worn: [1]),
            outfit(shirt, oldJeans, loafers, worn: [45]),
        ])
        let names = insights.notWornLately.map(\.item.name)
        #expect(names == ["Old jeans"])
        #expect(insights.notWornLately.first?.lastWorn != nil)
    }

    @Test func emptyWardrobe() {
        let insights = compute([])
        #expect(insights.totalItems == 0)
        #expect(insights.categories.isEmpty)
        #expect(insights.versatile.isEmpty)
        #expect(insights.needsMatch.isEmpty)
        #expect(!insights.hasWearHistory)
    }
}
