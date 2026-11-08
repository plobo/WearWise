import Foundation

/// Colour pairing rules. Deterministic and explainable.
enum ColorHarmony {
    static let neutrals: Set<ClothingColor> = [.black, .white, .grey, .navy, .beige, .brown]

    /// Neutral pairs that are usually avoided.
    private static let awkwardNeutralPairs: Set<Set<ClothingColor>> = [
        [.black, .navy], [.black, .brown],
    ]

    /// Colour + colour pairs that work well together.
    private static let goodColorPairs: Set<Set<ClothingColor>> = [
        [.lightBlue, .blue], [.lightBlue, .pink], [.lightBlue, .olive], [.lightBlue, .burgundy],
        [.olive, .burgundy], [.olive, .pink], [.blue, .orange], [.green, .pink],
    ]

    static func isNeutral(_ color: ClothingColor) -> Bool { neutrals.contains(color) }

    /// 0...1, higher is a better pairing.
    static func score(_ a: ClothingColor, _ b: ClothingColor) -> Double {
        if a == b { return isNeutral(a) ? 0.65 : 0.3 }
        let pair: Set<ClothingColor> = [a, b]
        switch (isNeutral(a), isNeutral(b)) {
        case (true, true):
            return awkwardNeutralPairs.contains(pair) ? 0.4 : 0.9
        case (true, false), (false, true):
            return 0.85
        case (false, false):
            return goodColorPairs.contains(pair) ? 0.7 : 0.25
        }
    }
}

struct OutfitSuggestion: Identifiable, Equatable, Sendable {
    let top: ClothingItem
    let bottom: ClothingItem
    let shoes: ClothingItem
    /// How well the pieces go together, 0...1. Drives the rating and the minimum-quality cut-off.
    let score: Double
    let reasons: [String]
    /// Ordering score: `score` lowered for recently worn pieces. Equal to `score` without history.
    var rankScore: Double

    init(top: ClothingItem, bottom: ClothingItem, shoes: ClothingItem, score: Double, reasons: [String], rankScore: Double? = nil) {
        self.top = top
        self.bottom = bottom
        self.shoes = shoes
        self.score = score
        self.reasons = reasons
        self.rankScore = rankScore ?? score
    }

    var id: String { "\(bottom.id.uuidString)-\(shoes.id.uuidString)" }
    var itemIDs: [UUID] { [top.id, bottom.id, shoes.id] }
    var key: OutfitKey { OutfitKey(topID: top.id, bottomID: bottom.id, shoesID: shoes.id) }

    var title: String { "\(bottom.name) + \(shoes.name)" }

    var rating: String {
        switch score {
        case 0.8...: "Great match"
        case 0.65..<0.8: "Good match"
        default: "Works"
        }
    }
}

enum MatchResult: Equatable, Sendable {
    case suggestions([OutfitSuggestion])
    /// The wardrobe lacks the pieces needed.
    case missingPieces(needsBottoms: Bool, needsShoes: Bool)
    /// Pieces exist but none go together well enough.
    case noGoodMatches
    /// Every good match for this top was hidden by the user.
    case allHidden
}

/// Suggests pants + shoes for a top, using only items in the wardrobe.
enum OutfitMatcher {
    static let minimumScore = 0.6

    /// Pants worn this recently (in days) are ranked lower, and shoes slightly lower.
    static let recentBottomDays = 2
    static let recentShoesDays = 1
    static let recentBottomPenalty = 0.12
    static let recentShoesPenalty = 0.04

    static func match(
        top: ClothingItem,
        wardrobe: [ClothingItem],
        context: MatchContext = MatchContext(),
        limit: Int = 5
    ) -> MatchResult {
        let bottoms = wardrobe.filter { $0.category == .bottoms && $0.id != top.id }
        let shoes = wardrobe.filter { $0.category == .shoes && $0.id != top.id }
        if bottoms.isEmpty || shoes.isEmpty {
            return .missingPieces(needsBottoms: bottoms.isEmpty, needsShoes: shoes.isEmpty)
        }

        var candidates: [OutfitSuggestion] = []
        for bottom in bottoms {
            for shoe in shoes {
                let key = OutfitKey(topID: top.id, bottomID: bottom.id, shoesID: shoe.id)
                guard !context.hidden.contains(key),
                      let suggestion = evaluate(top: top, bottom: bottom, shoes: shoe, context: context),
                      suggestion.score >= minimumScore
                else { continue }
                candidates.append(suggestion)
            }
        }
        candidates.sort { a, b in
            if a.rankScore != b.rankScore { return a.rankScore > b.rankScore }
            return a.title.localizedStandardCompare(b.title) == .orderedAscending
        }

        // Keep variety: no pants or shoes more than twice in the list.
        var picked: [OutfitSuggestion] = []
        var bottomUses: [UUID: Int] = [:]
        var shoeUses: [UUID: Int] = [:]
        for candidate in candidates where picked.count < limit {
            guard bottomUses[candidate.bottom.id, default: 0] < 2, shoeUses[candidate.shoes.id, default: 0] < 2 else { continue }
            picked.append(candidate)
            bottomUses[candidate.bottom.id, default: 0] += 1
            shoeUses[candidate.shoes.id, default: 0] += 1
        }

        let valid = picked.filter { isValid($0, wardrobe: wardrobe) }
        if valid.isEmpty {
            // Everything that matched was hidden by the user: say so rather than "no matches".
            let anyHidden = context.hidden.contains { $0.topID == top.id }
            return anyHidden ? .allHidden : .noGoodMatches
        }
        return .suggestions(valid)
    }

    /// Scores one combination, or nil if the dress levels are too far apart.
    static func evaluate(
        top: ClothingItem,
        bottom: ClothingItem,
        shoes: ClothingItem,
        context: MatchContext = MatchContext()
    ) -> OutfitSuggestion? {
        let levels = [top, bottom, shoes].map { level($0.formality) }
        let spread = levels.max()! - levels.min()!
        guard spread < 2 else { return nil }

        let topBottom = ColorHarmony.score(top.primaryColor, bottom.primaryColor)
        let topShoes = ColorHarmony.score(top.primaryColor, shoes.primaryColor)
        let bottomShoes = ColorHarmony.score(bottom.primaryColor, shoes.primaryColor)
        let colorScore = 0.45 * topBottom + 0.35 * topShoes + 0.2 * bottomShoes
        let formalityScore = spread == 0 ? 1.0 : 0.55
        let favoriteBonus = [bottom, shoes].filter(\.isFavorite).isEmpty ? 0 : 0.02
        let score = min(1, 0.6 * colorScore + 0.4 * formalityScore + favoriteBonus)

        var reasonList = reasons(top: top, bottom: bottom, shoes: shoes, topBottom: topBottom, bottomShoes: bottomShoes, spread: spread)
        var penalty = 0.0
        if let days = context.daysSinceWorn(bottom.id), days <= recentBottomDays {
            penalty += recentBottomPenalty
            reasonList.append("You wore the \(bottom.name.lowercased()) \(dayPhrase(days))")
        }
        if let days = context.daysSinceWorn(shoes.id), days <= recentShoesDays {
            penalty += recentShoesPenalty
        }

        return OutfitSuggestion(
            top: top,
            bottom: bottom,
            shoes: shoes,
            score: score,
            reasons: reasonList,
            rankScore: max(0, score - penalty)
        )
    }

    private static func dayPhrase(_ days: Int) -> String {
        switch days {
        case ...0: "today"
        case 1: "yesterday"
        default: "\(days) days ago"
        }
    }

    /// Critical rule: every suggested item must exist in the wardrobe, with the right roles and no repeats.
    static func isValid(_ suggestion: OutfitSuggestion, wardrobe: [ClothingItem]) -> Bool {
        let owned = Dictionary(wardrobe.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        guard Set(suggestion.itemIDs).count == 3,
              suggestion.itemIDs.allSatisfy({ owned[$0] != nil }),
              owned[suggestion.bottom.id]?.category == .bottoms,
              owned[suggestion.shoes.id]?.category == .shoes
        else { return false }
        return true
    }

    private static func level(_ formality: Formality) -> Int {
        switch formality {
        case .casual: 0
        case .smartCasual: 1
        case .formal: 2
        }
    }

    private static func reasons(
        top: ClothingItem, bottom: ClothingItem, shoes: ClothingItem,
        topBottom: Double, bottomShoes: Double, spread: Int
    ) -> [String] {
        let t = top.primaryColor.displayName.lowercased()
        let b = bottom.primaryColor.displayName.lowercased()
        let s = shoes.primaryColor.displayName.lowercased()
        var result: [String] = []

        if top.primaryColor == bottom.primaryColor {
            result.append(ColorHarmony.isNeutral(top.primaryColor) ? "Tonal \(t) look" : "Lots of \(t). A bold choice")
        } else if topBottom >= 0.85 {
            result.append(ColorHarmony.isNeutral(bottom.primaryColor)
                          ? "\(b.capitalized) pants keep the \(t) top in focus"
                          : "\(t.capitalized) top balances the \(b) pants")
        } else if topBottom >= 0.65 {
            result.append("\(t.capitalized) and \(b) work well together")
        } else {
            result.append("\(t.capitalized) with \(b) is a bolder pairing")
        }

        if ColorHarmony.isNeutral(shoes.primaryColor) {
            result.append(bottomShoes < 0.5 ? "\(s.capitalized) shoes are a less usual pick with \(b)" : "\(s.capitalized) shoes keep it grounded")
        } else {
            result.append("\(s.capitalized) shoes add a statement")
        }

        if spread == 0 {
            result.append("All \(top.formality.displayName.lowercased())")
        } else {
            let levels = Set([top.formality, bottom.formality, shoes.formality]).sorted { level($0) < level($1) }
            result.append("Mixes \(levels.map { $0.displayName.lowercased() }.joined(separator: " and "))")
        }
        return result
    }
}
