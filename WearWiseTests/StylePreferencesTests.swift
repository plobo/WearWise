import Foundation
import Testing
@testable import WearWise

struct StylePreferencesModelTests {
    @Test func lovingAColourRemovesItFromAvoidedAndViceVersa() {
        var prefs = StylePreferences()
        prefs.toggleAvoided(.red)
        prefs.toggleFavorite(.red)
        #expect(prefs.favoriteColors == [.red])
        #expect(prefs.avoidedColors.isEmpty)
        prefs.toggleAvoided(.red)
        #expect(prefs.avoidedColors == [.red])
        #expect(prefs.favoriteColors.isEmpty)
        prefs.toggleAvoided(.red)
        #expect(prefs.isEmpty)
    }
}

@MainActor
struct PreferencesStoreTests {
    @Test func persistsAcrossInstances() throws {
        let suite = "PreferencesTest-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = PreferencesStore(defaults: defaults)
        store.toggleFavorite(.navy)
        store.toggleAvoided(.orange)
        store.setUsualFormality(.smartCasual)

        let reopened = PreferencesStore(defaults: defaults)
        #expect(reopened.preferences == StylePreferences(favoriteColors: [.navy], avoidedColors: [.orange], usualFormality: .smartCasual))
        reopened.reset()
        #expect(PreferencesStore(defaults: defaults).preferences.isEmpty)
    }
}

struct PreferenceMatchingTests {
    let shirt = makeItem("White shirt", .tops, .white, .smartCasual)
    let navyChinos = makeItem("Navy chinos", .bottoms, .navy, .smartCasual)
    let greyTrousers = makeItem("Grey trousers", .bottoms, .grey, .smartCasual)
    let brownLoafers = makeItem("Brown loafers", .shoes, .brown, .smartCasual)
    let beigeJacket = makeItem("Beige jacket", .outerwear, .beige, .smartCasual)

    var wardrobe: [ClothingItem] { [shirt, navyChinos, greyTrousers, brownLoafers] }

    private func suggestions(_ prefs: StylePreferences, _ items: [ClothingItem]? = nil) -> [OutfitSuggestion] {
        var context = MatchContext()
        context.preferences = prefs
        if case .suggestions(let list) = OutfitMatcher.match(top: shirt, wardrobe: items ?? wardrobe, context: context) { return list }
        Issue.record("Expected suggestions")
        return []
    }

    @Test func baselineOrder() {
        // Without preferences, ties break by title: Grey before Navy.
        #expect(suggestions(.none).map(\.bottom?.name) == ["Grey trousers", "Navy chinos"])
    }

    @Test func favouriteColourMovesUpAndSaysSo() {
        let list = suggestions(StylePreferences(favoriteColors: [.navy]))
        #expect(list.first?.bottom?.id == navyChinos.id)
        #expect(list.first?.preferenceNote == "Uses navy, one of your favourite colours")
        #expect(list.first?.summary.hasSuffix("Uses navy, one of your favourite colours.") == true)
    }

    @Test func avoidedColourMovesDownButStaysAvailable() {
        let list = suggestions(StylePreferences(avoidedColors: [.grey]))
        #expect(list.map(\.bottom?.id) == [navyChinos.id, greyTrousers.id])
        #expect(list.last?.preferenceNote == "Includes grey, a colour you avoid")
    }

    @Test func preferencesNeverChangeScoreRatingOrWhichOutfitsQualify() {
        let plain = suggestions(.none)
        let tasteful = suggestions(StylePreferences(favoriteColors: [.navy], avoidedColors: [.grey], usualFormality: .casual))
        #expect(Set(plain.map(\.key)) == Set(tasteful.map(\.key)))
        for s in tasteful {
            let original = plain.first { $0.key == s.key }
            #expect(s.score == original?.score)
            #expect(s.rating == original?.rating)
        }
    }

    @Test func usualStyleGivesASmallBoost() {
        let casualTrousers = makeItem("Grey trousers", .bottoms, .grey, .casual)
        let boosted = OutfitMatcher.preferenceEffect(for: [navyChinos, brownLoafers], preferences: StylePreferences(usualFormality: .smartCasual))
        let notBoosted = OutfitMatcher.preferenceEffect(for: [casualTrousers, brownLoafers], preferences: StylePreferences(usualFormality: .smartCasual))
        #expect(boosted.0 == OutfitMatcher.usualFormalityBonus)
        #expect(notBoosted.0 == 0)
        #expect(boosted.1 == nil, "Usual style has no note of its own")
    }

    @Test func recencyNoteTakesPriorityInSummary() {
        var s = OutfitMatcher.evaluate(top: shirt, bottom: navyChinos, shoes: brownLoafers)!
        s.preferenceNote = "Uses navy, one of your favourite colours"
        s.recencyNote = "You wore the navy chinos yesterday"
        #expect(s.summary.hasSuffix("You wore the navy chinos yesterday."))
        #expect(s.allReasons.contains("Uses navy, one of your favourite colours"), "Still given to the AI as a fact")
    }

    @Test func avoidedColourExtrasAreNotSuggested() {
        let base = OutfitMatcher.evaluate(top: shirt, bottom: navyChinos, shoes: brownLoafers)!
        #expect(OutfitMatcher.bestLayer(for: base, in: [beigeJacket])?.id == beigeJacket.id, "Suggested without preferences")
        let avoidBeige = StylePreferences(avoidedColors: [.beige])
        #expect(OutfitMatcher.bestLayer(for: base, in: [beigeJacket], preferences: avoidBeige) == nil)
    }

    @Test func favouriteColourWinsTiesBetweenExtras() {
        let base = OutfitMatcher.evaluate(top: shirt, bottom: navyChinos, shoes: brownLoafers)!
        let greyJacket = makeItem("Grey jacket", .outerwear, .grey, .smartCasual)
        let charcoal = makeItem("Another grey jacket", .outerwear, .grey, .smartCasual)
        let favouriteNavy = makeItem("Zed navy jacket", .outerwear, .navy, .smartCasual)
        // Navy vs navy chinos is tonal (0.65) and loses on harmony; favourite colour only breaks near-ties.
        #expect(OutfitMatcher.bestLayer(for: base, in: [greyJacket, charcoal, favouriteNavy], preferences: StylePreferences(favoriteColors: [.navy]))?.primaryColor == .grey)
    }
}
