import Foundation
import SwiftData
import Testing
@testable import WearWise

/// A controllable clock for date-dependent behaviour.
@MainActor
final class TestClock {
    var now: Date
    init(_ now: Date) { self.now = now }
    func advance(days: Int) { now = now.addingTimeInterval(TimeInterval(days) * 86_400) }
}

var utcCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

/// Noon UTC on 7 Nov 2026, so ±1 day never crosses into an unexpected day.
let referenceNoon = Date(timeIntervalSince1970: 1_794_052_800)

// MARK: - Outfit store

@MainActor
struct OutfitStoreTests {
    let key = OutfitKey(topID: UUID(), bottomID: UUID(), shoesID: UUID())

    private func makeStore(clock: TestClock = TestClock(referenceNoon), container: ModelContainer? = nil) throws -> OutfitStore {
        let container = try container ?? ModelContainerFactory.make(inMemory: true)
        return OutfitStore(repository: SwiftDataOutfitRepository(container: container), now: { clock.now }, calendar: utcCalendar)
    }

    @Test func savingAndUnsaving() throws {
        let store = try makeStore()
        try store.toggleSaved(key)
        #expect(store.isSaved(key))
        #expect(store.saved.map(\.key) == [key])

        try store.toggleSaved(key)
        #expect(!store.isSaved(key))
        #expect(store.outfits.isEmpty, "Records with no state are dropped")
    }

    @Test func woreTodayTogglesAndCountsOncePerDay() throws {
        let clock = TestClock(referenceNoon)
        let store = try makeStore(clock: clock)

        try store.toggleWornToday(key)
        #expect(store.isWornToday(key))
        try store.toggleWornToday(key)
        #expect(!store.isWornToday(key), "Second tap the same day undoes it")
        #expect(store.outfits.isEmpty)

        try store.toggleWornToday(key)
        clock.advance(days: 1)
        #expect(!store.isWornToday(key))
        try store.toggleWornToday(key)
        #expect(store.outfit(for: key)?.timesWorn == 2)
        #expect(store.recentlyWorn.map(\.key) == [key])
    }

    @Test func hidingUnsavesAndSavingUnhides() throws {
        let store = try makeStore()
        try store.toggleSaved(key)
        try store.hide(key)
        #expect(!store.isSaved(key))
        #expect(store.hidden.map(\.key) == [key])
        #expect(store.matchContext().hidden == [key])

        try store.toggleSaved(key)
        #expect(store.hidden.isEmpty)
    }

    @Test func unhideRestoresSuggestion() throws {
        let store = try makeStore()
        try store.hide(key)
        try store.unhide(key)
        #expect(store.matchContext().hidden.isEmpty)
    }

    @Test func wearHistoryPersistsAcrossRelaunch() throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let clock = TestClock(referenceNoon)
        let first = try makeStore(clock: clock, container: container)
        try first.toggleSaved(key)
        try first.toggleWornToday(key)

        #expect(first.recentlyWorn.isEmpty, "Saved outfits aren't repeated under Recently worn")

        let reopened = try makeStore(clock: clock, container: container)
        let outfit = try #require(reopened.outfit(for: key))
        #expect(outfit.isSaved)
        #expect(outfit.timesWorn == 1)
    }

    @Test func lastWornPerItemUsesMostRecentOutfit() throws {
        let clock = TestClock(referenceNoon)
        let store = try makeStore(clock: clock)
        let sharedShoes = key.shoesID
        let other = OutfitKey(topID: UUID(), bottomID: UUID(), shoesID: sharedShoes)

        try store.toggleWornToday(key)
        clock.advance(days: 2)
        try store.toggleWornToday(other)

        let context = store.matchContext()
        #expect(context.daysSinceWorn(sharedShoes) == 0)
        #expect(context.daysSinceWorn(key.bottomID!) == 2)
        #expect(context.daysSinceWorn(UUID()) == nil)
    }
}

// MARK: - Deleting clothes removes their outfits

@MainActor
struct OutfitCascadeTests {
    @Test func deletingAnItemRemovesOutfitsThatUseIt() throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let wardrobe = WardrobeStore(
            repository: SwiftDataClothingRepository(container: container),
            imageStore: LocalImageStore(baseDirectory: tempDirectory())
        )
        let outfits = OutfitStore(repository: SwiftDataOutfitRepository(container: container))
        wardrobe.onItemDeleted = { try outfits.removeOutfits(containing: $0) }

        var shirtDraft = completeDraft("Shirt"); shirtDraft.category = .tops
        var shoeDraft = completeDraft("Shoes"); shoeDraft.category = .shoes
        let shirt = try wardrobe.add(shirtDraft, photo: samplePhoto(), status: .manual)
        let pants = try wardrobe.add(completeDraft("Pants"), photo: samplePhoto(), status: .manual)
        let shoes = try wardrobe.add(shoeDraft, photo: samplePhoto(), status: .manual)
        let otherPants = try wardrobe.add(completeDraft("Other pants"), photo: samplePhoto(), status: .manual)

        let doomed = OutfitKey(topID: shirt.id, bottomID: pants.id, shoesID: shoes.id)
        let kept = OutfitKey(topID: shirt.id, bottomID: otherPants.id, shoesID: shoes.id)
        try outfits.toggleSaved(doomed)
        try outfits.toggleSaved(kept)

        try wardrobe.delete(pants)

        #expect(outfits.outfits.map(\.key) == [kept])
        outfits.reload()
        #expect(outfits.outfits.map(\.key) == [kept], "Removed from storage too")
    }

    @Test func resolvedOutfitSkipsMissingItems() {
        let top = makeItem("Top", .tops, .white, .casual)
        let bottom = makeItem("Pants", .bottoms, .navy, .casual)
        let shoes = makeItem("Shoes", .shoes, .white, .casual)
        let outfit = Outfit(id: UUID(), key: OutfitKey(topID: top.id, bottomID: bottom.id, shoesID: shoes.id),
                            isSaved: true, isHidden: false, wornDates: [], dateCreated: .now)
        #expect(ResolvedOutfit(outfit, wardrobe: [top, bottom, shoes]) != nil)
        #expect(ResolvedOutfit(outfit, wardrobe: [top, shoes]) == nil)
    }
}

// MARK: - Matching with history

struct MatchingWithHistoryTests {
    let shirt = makeItem("Light blue oxford", .tops, .lightBlue, .smartCasual)
    let chinos = makeItem("Beige chinos", .bottoms, .beige, .smartCasual)
    let greyTrousers = makeItem("Grey trousers", .bottoms, .grey, .smartCasual)
    let loafers = makeItem("Brown loafers", .shoes, .brown, .smartCasual)

    var wardrobe: [ClothingItem] { [shirt, chinos, greyTrousers, loafers] }

    private func suggestions(_ context: MatchContext) -> [OutfitSuggestion] {
        if case .suggestions(let list) = OutfitMatcher.match(top: shirt, wardrobe: wardrobe, context: context) { return list }
        return []
    }

    private func context(lastWorn: [UUID: Int] = [:], hidden: Set<OutfitKey> = []) -> MatchContext {
        MatchContext(
            hidden: hidden,
            lastWorn: lastWorn.mapValues { referenceNoon.addingTimeInterval(TimeInterval(-$0) * 86_400) },
            now: referenceNoon,
            calendar: utcCalendar
        )
    }

    @Test func baselineRanksChinosFirst() {
        #expect(suggestions(context()).first?.bottom?.id == chinos.id)
    }

    @Test func hiddenCombinationIsNeverSuggested() {
        let hiddenKey = OutfitKey(topID: shirt.id, bottomID: chinos.id, shoesID: loafers.id)
        let list = suggestions(context(hidden: [hiddenKey]))
        #expect(!list.contains { $0.key == hiddenKey })
        #expect(list.first?.bottom?.id == greyTrousers.id)
    }

    @Test func allHiddenIsReportedSeparately() {
        let keys: Set<OutfitKey> = [
            OutfitKey(topID: shirt.id, bottomID: chinos.id, shoesID: loafers.id),
            OutfitKey(topID: shirt.id, bottomID: greyTrousers.id, shoesID: loafers.id),
        ]
        #expect(OutfitMatcher.match(top: shirt, wardrobe: wardrobe, context: context(hidden: keys)) == .allHidden)
    }

    @Test func pantsWornYesterdayRankLowerAndSaySo() {
        let list = suggestions(context(lastWorn: [chinos.id: 1]))
        #expect(list.first?.bottom?.id == greyTrousers.id)
        let chinosOutfit = list.first { $0.bottom?.id == chinos.id }
        #expect(chinosOutfit?.reasons.last == "You wore the beige chinos yesterday")
        #expect(chinosOutfit?.rating == "Great match", "Rating reflects fit, not recency")
    }

    @Test func pantsWornLongAgoAreNotPenalised() {
        let list = suggestions(context(lastWorn: [chinos.id: 5]))
        #expect(list.first?.bottom?.id == chinos.id)
        #expect(list.first?.reasons.contains { $0.hasPrefix("You wore") } == false)
    }

    @Test func recencyNeverDropsOutfitsBelowTheQualityBar() {
        let worn = suggestions(context(lastWorn: [chinos.id: 0, greyTrousers.id: 0, loafers.id: 0]))
        #expect(worn.count == suggestions(context()).count)
    }
}

// MARK: - Migration

@MainActor
struct OutfitMigrationTests {
    @Test func migratesVersion2StoreAndAddsOutfits() throws {
        let dir = tempDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "wardrobe.store")
        var item = makeItem("Navy chinos", .bottoms, .navy, .smartCasual)
        item.cutoutPath = "x_cutout.png"

        do {
            let v2Schema = Schema(versionedSchema: WardrobeSchemaV2.self)
            let v2 = try ModelContainer(for: v2Schema, configurations: ModelConfiguration(schema: v2Schema, url: url))
            v2.mainContext.insert(WardrobeSchemaV2.ClothingItemRecord(item: item))
            try v2.mainContext.save()
        }

        let container = try ModelContainerFactory.make(storeURL: url)
        let items = try SwiftDataClothingRepository(container: container).allItems()
        #expect(items.map(\.id) == [item.id])
        #expect(items.first?.cutoutPath == "x_cutout.png")

        let outfits = SwiftDataOutfitRepository(container: container)
        #expect(try outfits.allOutfits().isEmpty)
        let outfit = Outfit(id: UUID(), key: OutfitKey(topID: UUID(), bottomID: item.id, shoesID: UUID()),
                            isSaved: true, isHidden: false, wornDates: [], dateCreated: .now)
        try outfits.insert(outfit)
        #expect(try outfits.allOutfits() == [outfit])
    }
}
