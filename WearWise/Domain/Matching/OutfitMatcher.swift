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
    /// Optional accessories (at most a belt and one other). Never affect the score.
    var accessories: [ClothingItem] = []
    /// How well the pieces go together, 0...1. Drives the rating and the minimum-quality cut-off.
    let score: Double
    /// Core reasons, always ending with the formality note: colour, shoes (or dress + shoes), formality.
    let reasons: [String]
    /// "You wore the beige chinos yesterday", when the pants were worn recently.
    var recencyNote: String?
    /// "Uses navy, one of your favourite colours" or "Includes red, a colour you avoid".
    var preferenceNote: String?
    /// One line per optional extra ("The brown belt matches your brown loafers").
    var extraReasons: [String] = []
    /// Ordering score: `score` lowered for recently worn pieces. Equal to `score` without history.
    var rankScore: Double

    init(
        top: ClothingItem, bottom: ClothingItem?, shoes: ClothingItem, layer: ClothingItem? = nil,
        score: Double, reasons: [String], recencyNote: String? = nil, preferenceNote: String? = nil,
        rankScore: Double? = nil
    ) {
        self.top = top
        self.bottom = bottom
        self.shoes = shoes
        self.layer = layer
        self.score = score
        self.reasons = reasons
        self.recencyNote = recencyNote
        self.preferenceNote = preferenceNote
        self.rankScore = rankScore ?? score
    }

    var id: String { [bottom?.id.uuidString ?? "none", shoes.id.uuidString].joined(separator: "-") }
    var isDressOutfit: Bool { bottom == nil }
    /// The core pieces (without optional extras).
    var itemIDs: [UUID] { [top.id, bottom?.id, shoes.id].compactMap { $0 } }
    /// The optional layer and accessories, in display order.
    var extras: [ClothingItem] { [layer].compactMap { $0 } + accessories }
    var key: OutfitKey { OutfitKey(topID: top.id, bottomID: bottom?.id, shoesID: shoes.id) }

    var title: String {
        if let bottom { return "\(bottom.name) + \(shoes.name)" }
        return "\(top.name) + \(shoes.name)"
    }

    /// Everything the app knows about why this works, used as facts for AI explanations.
    var allReasons: [String] { reasons + [recencyNote, preferenceNote].compactMap { $0 } + extraReasons }

    /// At most three short sentences for display without AI: colour, shoes, then the most personal
    /// note (recent wear, then preference) in place of the formality note. Extras have their own row.
    var summary: String {
        var lines = reasons
        if let note = recencyNote ?? preferenceNote {
            if lines.count > 1 { lines.removeLast() }
            lines.append(note)
        }
        return lines.joined(separator: ". ") + "."
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

        let completed = picked.map { addingExtras(to: $0, from: wardrobe, preferences: context.preferences) }
        let valid = completed.filter { isValid($0, wardrobe: wardrobe) }
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

        let reasonList = bottom.map {
            reasons(top: top, bottom: $0, shoes: shoes, topBottom: topBottom, bottomShoes: bottomShoes, spread: spread)
        } ?? dressReasons(dress: top, shoes: shoes, spread: spread)

        var penalty = 0.0
        var recencyNote: String?
        if let bottom, let days = context.daysSinceWorn(bottom.id), days <= recentBottomDays {
            penalty += recentBottomPenalty
            recencyNote = "You wore the \(bottom.name.lowercased()) \(dayPhrase(days))"
        }
        if let days = context.daysSinceWorn(shoes.id), days <= recentShoesDays {
            penalty += recentShoesPenalty
        }
        let (preferenceAdjustment, preferenceNote) = preferenceEffect(
            for: [bottom, shoes].compactMap { $0 }, preferences: context.preferences
        )

        return OutfitSuggestion(
            top: top,
            bottom: bottom,
            shoes: shoes,
            score: score,
            reasons: reasonList,
            recencyNote: recencyNote,
            preferenceNote: preferenceNote,
            rankScore: max(0, score - penalty + preferenceAdjustment)
        )
    }

    static let favoriteColorBonus = 0.03
    static let avoidedColorPenalty = 0.15
    static let usualFormalityBonus = 0.04

    /// How the user's taste shifts the order of an outfit, and the note that explains it.
    /// Only the pieces the app chose count (not the starting piece the user picked).
    static func preferenceEffect(for chosen: [ClothingItem], preferences: StylePreferences) -> (Double, String?) {
        guard !preferences.isEmpty, !chosen.isEmpty else { return (0, nil) }
        var adjustment = 0.0
        var note: String?

        let avoided = chosen.filter { preferences.avoidedColors.contains($0.primaryColor) }
        let loved = chosen.filter { preferences.favoriteColors.contains($0.primaryColor) }
        if let first = avoided.first {
            adjustment -= avoidedColorPenalty * Double(avoided.count)
            note = "Includes \(first.primaryColor.displayName.lowercased()), a colour you avoid"
        } else if let first = loved.first {
            adjustment += favoriteColorBonus * Double(loved.count)
            note = "Uses \(first.primaryColor.displayName.lowercased()), one of your favourite colours"
        }
        if let usual = preferences.usualFormality, chosen.allSatisfy({ $0.formality == usual }) {
            adjustment += usualFormalityBonus
        }
        return (adjustment, note)
    }

    /// The outer layer that best suits the outfit, if any pairs well on colour and dress level.
    static func bestLayer(for suggestion: OutfitSuggestion, in wardrobe: [ClothingItem], preferences: StylePreferences = .none) -> ClothingItem? {
        let core = [suggestion.top, suggestion.bottom, suggestion.shoes].compactMap { $0 }
        let lower = suggestion.bottom ?? suggestion.shoes
        let scored: [(item: ClothingItem, score: Double)] = wardrobe.compactMap { layer in
            guard layer.category == .outerwear, !suggestion.itemIDs.contains(layer.id),
                  !preferences.avoidedColors.contains(layer.primaryColor),
                  formalitySpread(core + [layer]) < 2
            else { return nil }
            let withTop = ColorHarmony.score(layer.primaryColor, suggestion.top.primaryColor)
            let withLower = ColorHarmony.score(layer.primaryColor, lower.primaryColor)
            guard min(withTop, withLower) >= minimumLayerHarmony else { return nil }
            return (layer, (withTop + withLower) / 2 + (layer.isFavorite ? 0.02 : 0) + favoriteColorBoost(layer, preferences))
        }
        return scored.max { a, b in
            a.score != b.score ? a.score < b.score : a.item.name.localizedStandardCompare(b.item.name) == .orderedDescending
        }?.item
    }

    /// The belt that best suits an outfit with pants. The classic rule: the belt matches the shoes.
    /// With white or coloured shoes (usually sneakers), a neutral belt that suits the pants is fine.
    static func bestBelt(
        for suggestion: OutfitSuggestion, in wardrobe: [ClothingItem], preferences: StylePreferences = .none
    ) -> (belt: ClothingItem, matchesShoes: Bool)? {
        guard let bottom = suggestion.bottom else { return nil }
        let core = [suggestion.top, bottom, suggestion.shoes]
        let shoeColor = suggestion.shoes.primaryColor
        let leatherTones: Set<ClothingColor> = [.brown, .burgundy]
        let relaxedShoes = shoeColor == .white || !ColorHarmony.isNeutral(shoeColor)

        let scored: [(item: ClothingItem, score: Double, matchesShoes: Bool)] = wardrobe.compactMap { belt in
            guard belt.resolvedAccessoryKind == .belt, !preferences.avoidedColors.contains(belt.primaryColor),
                  formalitySpread(core + [belt]) < 2 else { return nil }
            let favorite = belt.isFavorite ? 0.02 : 0
            if belt.primaryColor == shoeColor { return (belt, 1 + favorite, true) }
            if leatherTones.contains(belt.primaryColor), leatherTones.contains(shoeColor) { return (belt, 0.8 + favorite, true) }
            if relaxedShoes, ColorHarmony.isNeutral(belt.primaryColor),
               ColorHarmony.score(belt.primaryColor, bottom.primaryColor) >= 0.85 {
                return (belt, 0.6 + favorite, false)
            }
            return nil
        }
        return scored.max { a, b in
            a.score != b.score ? a.score < b.score : a.item.name.localizedStandardCompare(b.item.name) == .orderedDescending
        }.map { ($0.item, $0.matchesShoes) }
    }

    /// At most one non-belt accessory whose colours suit the outfit and whose formality fits.
    static func bestAccessory(for suggestion: OutfitSuggestion, in wardrobe: [ClothingItem], preferences: StylePreferences = .none) -> ClothingItem? {
        let core = [suggestion.top, suggestion.bottom, suggestion.shoes].compactMap { $0 }
        let lower = suggestion.bottom ?? suggestion.shoes
        let scored: [(item: ClothingItem, score: Double)] = wardrobe.compactMap { item in
            guard let kind = item.resolvedAccessoryKind, kind != .belt, !preferences.avoidedColors.contains(item.primaryColor),
                  formalitySpread(core + [item]) < 2 else { return nil }
            let withTop = ColorHarmony.score(item.primaryColor, suggestion.top.primaryColor)
            let withLower = ColorHarmony.score(item.primaryColor, lower.primaryColor)
            guard min(withTop, withLower) >= minimumLayerHarmony else { return nil }
            return (item, (withTop + withLower) / 2 + (item.isFavorite ? 0.02 : 0) + favoriteColorBoost(item, preferences))
        }
        return scored.max { a, b in
            a.score != b.score ? a.score < b.score : a.item.name.localizedStandardCompare(b.item.name) == .orderedDescending
        }?.item
    }

    /// Adds the optional layer, belt and accessory that suit the outfit. Never changes score or order.
    static func addingExtras(
        to suggestion: OutfitSuggestion, from wardrobe: [ClothingItem], preferences: StylePreferences = .none
    ) -> OutfitSuggestion {
        var result = suggestion
        if let layer = bestLayer(for: suggestion, in: wardrobe, preferences: preferences) {
            result.layer = layer
            result.extraReasons.append("The \(layer.name.lowercased()) works over it when it's cooler")
        }
        if let (belt, matchesShoes) = bestBelt(for: suggestion, in: wardrobe, preferences: preferences) {
            result.accessories.append(belt)
            result.extraReasons.append(matchesShoes
                ? "The \(belt.name.lowercased()) matches your \(suggestion.shoes.name.lowercased())"
                : "The \(belt.name.lowercased()) suits the \(suggestion.bottom?.name.lowercased() ?? "outfit")")
        }
        if let accessory = bestAccessory(for: suggestion, in: wardrobe, preferences: preferences) {
            result.accessories.append(accessory)
            result.extraReasons.append("The \(accessory.name.lowercased()) finishes the look")
        }
        return result
    }

    /// Extras in a favourite colour win ties against equally good alternatives.
    private static func favoriteColorBoost(_ item: ClothingItem, _ preferences: StylePreferences) -> Double {
        preferences.favoriteColors.contains(item.primaryColor) ? favoriteColorBonus : 0
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

        let accessoryIDs = suggestion.accessories.map(\.id)
        guard Set(accessoryIDs).count == accessoryIDs.count, !accessoryIDs.contains(where: allIDs.contains) else { return false }
        for accessory in suggestion.accessories {
            guard let item = owned[accessory.id], item.category == .accessories else { return false }
            if item.resolvedAccessoryKind == .belt, suggestion.bottom == nil { return false }
        }
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
