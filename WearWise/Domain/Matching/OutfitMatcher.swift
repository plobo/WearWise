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

/// One suggested outfit. `top` is the starting piece: a top or a dress.
struct OutfitSuggestion: Identifiable, Equatable, Sendable {
    let top: ClothingItem
    /// Nil when the starting piece is a dress.
    let bottom: ClothingItem?
    let shoes: ClothingItem
    /// Optional outer layer that goes with the outfit. Never affects the score.
    var layer: ClothingItem?
    /// How well the pieces go together, 0...1. Drives the rating and the minimum-quality cut-off.
    let score: Double
    var reasons: [String]
    /// Ordering score: `score` lowered for recently worn pieces. Equal to `score` without history.
    var rankScore: Double

    init(
        top: ClothingItem, bottom: ClothingItem?, shoes: ClothingItem, layer: ClothingItem? = nil,
        score: Double, reasons: [String], rankScore: Double? = nil
    ) {
        self.top = top
        self.bottom = bottom
        self.shoes = shoes
        self.layer = layer
        self.score = score
        self.reasons = reasons
        self.rankScore = rankScore ?? score
    }

    var id: String { [bottom?.id.uuidString ?? "none", shoes.id.uuidString].joined(separator: "-") }
    var isDressOutfit: Bool { bottom == nil }
    /// The core pieces (without the optional layer).
    var itemIDs: [UUID] { [top.id, bottom?.id, shoes.id].compactMap { $0 } }
    var key: OutfitKey { OutfitKey(topID: top.id, bottomID: bottom?.id, shoesID: shoes.id) }

    var title: String {
        if let bottom { return "\(bottom.name) + \(shoes.name)" }
        return "\(top.name) + \(shoes.name)"
    }

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
    /// Every good match for this piece was hidden by the user.
    case allHidden
}

/// Suggests what to wear with a top (pants + shoes) or a dress (shoes), plus an optional outer layer,
/// using only items in the wardrobe.
enum OutfitMatcher {
    static let minimumScore = 0.6
    /// A layer must pair at least this well with the outfit's main colours.
    static let minimumLayerHarmony = 0.65

    /// Pants worn this recently (in days) are ranked lower, and shoes slightly lower.
    static let recentBottomDays = 2
    static let recentShoesDays = 1
    static let recentBottomPenalty = 0.12
    static let recentShoesPenalty = 0.04

    /// Categories that can start an outfit.
    static let startingCategories: Set<ClothingCategory> = [.tops, .dresses]

    static func match(
        top: ClothingItem,
        wardrobe: [ClothingItem],
        context: MatchContext = MatchContext(),
        limit: Int = 5
    ) -> MatchResult {
        guard startingCategories.contains(top.category) else { return .noGoodMatches }
        let isDress = top.category == .dresses
        let bottoms = wardrobe.filter { $0.category == .bottoms && $0.id != top.id }
        let shoes = wardrobe.filter { $0.category == .shoes && $0.id != top.id }
        if shoes.isEmpty || (!isDress && bottoms.isEmpty) {
            return .missingPieces(needsBottoms: !isDress && bottoms.isEmpty, needsShoes: shoes.isEmpty)
        }

        let bottomOptions: [ClothingItem?] = isDress ? [nil] : bottoms.map { $0 }
        var candidates: [OutfitSuggestion] = []
        for bottom in bottomOptions {
            for shoe in shoes {
                let key = OutfitKey(topID: top.id, bottomID: bottom?.id, shoesID: shoe.id)
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
            if let bottomID = candidate.bottom?.id, bottomUses[bottomID, default: 0] >= 2 { continue }
            guard shoeUses[candidate.shoes.id, default: 0] < 2 else { continue }
            picked.append(candidate)
            if let bottomID = candidate.bottom?.id { bottomUses[bottomID, default: 0] += 1 }
            shoeUses[candidate.shoes.id, default: 0] += 1
        }

        let withLayers = picked.map { addingLayer(to: $0, from: wardrobe) }
        let valid = withLayers.filter { isValid($0, wardrobe: wardrobe) }
        if valid.isEmpty {
            // Everything that matched was hidden by the user: say so rather than "no matches".
            let anyHidden = context.hidden.contains { $0.topID == top.id }
            return anyHidden ? .allHidden : .noGoodMatches
        }
        return .suggestions(valid)
    }

    /// Scores one combination, or nil if the dress levels are too far apart.
    /// Pass `bottom: nil` when `top` is a dress.
    static func evaluate(
        top: ClothingItem,
        bottom: ClothingItem?,
        shoes: ClothingItem,
        context: MatchContext = MatchContext()
    ) -> OutfitSuggestion? {
        let pieces = [top, bottom, shoes].compactMap { $0 }
        let spread = formalitySpread(pieces)
        guard spread < 2 else { return nil }

        let topShoes = ColorHarmony.score(top.primaryColor, shoes.primaryColor)
        let colorScore: Double
        var topBottom = 0.0
        var bottomShoes = 0.0
        if let bottom {
            topBottom = ColorHarmony.score(top.primaryColor, bottom.primaryColor)
            bottomShoes = ColorHarmony.score(bottom.primaryColor, shoes.primaryColor)
            colorScore = 0.45 * topBottom + 0.35 * topShoes + 0.2 * bottomShoes
        } else {
            colorScore = topShoes
        }
        let formalityScore = spread == 0 ? 1.0 : 0.55
        let favoriteBonus = [bottom, shoes].compactMap { $0 }.filter(\.isFavorite).isEmpty ? 0 : 0.02
        let score = min(1, 0.6 * colorScore + 0.4 * formalityScore + favoriteBonus)

        var reasonList = bottom.map {
            reasons(top: top, bottom: $0, shoes: shoes, topBottom: topBottom, bottomShoes: bottomShoes, spread: spread)
        } ?? dressReasons(dress: top, shoes: shoes, spread: spread)

        var penalty = 0.0
        if let bottom, let days = context.daysSinceWorn(bottom.id), days <= recentBottomDays {
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

    /// The outer layer that best suits the outfit, if any pairs well on colour and dress level.
    static func bestLayer(for suggestion: OutfitSuggestion, in wardrobe: [ClothingItem]) -> ClothingItem? {
        let core = [suggestion.top, suggestion.bottom, suggestion.shoes].compactMap { $0 }
        let lower = suggestion.bottom ?? suggestion.shoes
        let scored: [(item: ClothingItem, score: Double)] = wardrobe.compactMap { layer in
            guard layer.category == .outerwear, !suggestion.itemIDs.contains(layer.id),
                  formalitySpread(core + [layer]) < 2
            else { return nil }
            let withTop = ColorHarmony.score(layer.primaryColor, suggestion.top.primaryColor)
            let withLower = ColorHarmony.score(layer.primaryColor, lower.primaryColor)
            guard min(withTop, withLower) >= minimumLayerHarmony else { return nil }
            return (layer, (withTop + withLower) / 2 + (layer.isFavorite ? 0.02 : 0))
        }
        return scored.max { a, b in
            a.score != b.score ? a.score < b.score : a.item.name.localizedStandardCompare(b.item.name) == .orderedDescending
        }?.item
    }

    static func addingLayer(to suggestion: OutfitSuggestion, from wardrobe: [ClothingItem]) -> OutfitSuggestion {
        guard let layer = bestLayer(for: suggestion, in: wardrobe) else { return suggestion }
        var result = suggestion
        result.layer = layer
        result.reasons.append("The \(layer.name.lowercased()) works over it when it's cooler")
        return result
    }

    private static func dayPhrase(_ days: Int) -> String {
        switch days {
        case ...0: "today"
        case 1: "yesterday"
        default: "\(days) days ago"
        }
    }

    /// Critical rule: every suggested item must exist in the wardrobe, in the right role, with no repeats.
    static func isValid(_ suggestion: OutfitSuggestion, wardrobe: [ClothingItem]) -> Bool {
        let owned = Dictionary(wardrobe.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let allIDs = suggestion.itemIDs + [suggestion.layer?.id].compactMap { $0 }
        guard Set(allIDs).count == allIDs.count,
              allIDs.allSatisfy({ owned[$0] != nil }),
              let start = owned[suggestion.top.id], startingCategories.contains(start.category),
              owned[suggestion.shoes.id]?.category == .shoes
        else { return false }

        if start.category == .dresses {
            guard suggestion.bottom == nil else { return false }
        } else {
            guard let bottom = suggestion.bottom, owned[bottom.id]?.category == .bottoms else { return false }
        }
        if let layer = suggestion.layer, owned[layer.id]?.category != .outerwear { return false }
        return true
    }

    private static func level(_ formality: Formality) -> Int {
        switch formality {
        case .casual: 0
        case .smartCasual: 1
        case .formal: 2
        }
    }

    private static func formalitySpread(_ items: [ClothingItem]) -> Int {
        let levels = items.map { level($0.formality) }
        return (levels.max() ?? 0) - (levels.min() ?? 0)
    }

    private static func formalityReason(_ items: [ClothingItem], spread: Int) -> String {
        if spread == 0 { return "All \(items[0].formality.displayName.lowercased())" }
        let levels = Set(items.map(\.formality)).sorted { level($0) < level($1) }
        return "Mixes \(levels.map { $0.displayName.lowercased() }.joined(separator: " and "))"
    }

    private static func dressReasons(dress: ClothingItem, shoes: ClothingItem, spread: Int) -> [String] {
        let d = dress.primaryColor.displayName.lowercased()
        let s = shoes.primaryColor.displayName.lowercased()
        let harmony = ColorHarmony.score(dress.primaryColor, shoes.primaryColor)
        var result: [String] = []
        if ColorHarmony.isNeutral(shoes.primaryColor) {
            result.append(harmony < 0.5 ? "\(s.capitalized) shoes are a less usual pick with \(d)" : "\(s.capitalized) shoes let the \(d) dress lead")
        } else if harmony >= 0.65 {
            result.append("\(s.capitalized) shoes pick up the \(d) dress nicely")
        } else {
            result.append("\(s.capitalized) shoes are a bold contrast to the \(d) dress")
        }
        result.append(formalityReason([dress, shoes], spread: spread))
        return result
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

        result.append(formalityReason([top, bottom, shoes], spread: spread))
        return result
    }
}
