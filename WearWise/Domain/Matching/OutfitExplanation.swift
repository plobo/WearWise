import Foundation

/// The facts an explanation may use. Built from a suggestion the app already chose and validated.
struct OutfitExplanationInput: Sendable, Hashable {
    struct Piece: Sendable, Hashable {
        let role: String
        let name: String
        let category: ClothingCategory
        let color: ClothingColor
        let formality: Formality
    }

    let pieces: [Piece]
    /// Rule-based reasons, used as the facts to rephrase and as the fallback text.
    let reasons: [String]

    init(_ suggestion: OutfitSuggestion) {
        var pieces = [Piece(role: suggestion.isDressOutfit ? "Dress" : "Top", item: suggestion.top)]
        if let bottom = suggestion.bottom { pieces.append(Piece(role: "Pants", item: bottom)) }
        pieces.append(Piece(role: "Shoes", item: suggestion.shoes))
        if let layer = suggestion.layer { pieces.append(Piece(role: "Optional layer", item: layer)) }
        self.pieces = pieces
        reasons = suggestion.reasons
    }

    var hasLayer: Bool { pieces.contains { $0.category == .outerwear } }

    var fallbackText: String { reasons.joined(separator: ". ") + "." }
}

extension OutfitExplanationInput.Piece {
    init(role: String, item: ClothingItem) {
        self.init(role: role, name: item.name, category: item.category, color: item.primaryColor, formality: item.formality)
    }
}

/// Deterministic checks on AI-written explanations. The model may phrase things; it may not
/// introduce clothes, materials, prices or styling changes that the app didn't choose.
enum OutfitExplanationValidator {
    static let maxLength = 300

    /// Clothing words the model might use to introduce a piece that isn't in the outfit.
    /// Words that are also common verbs or adjectives in styling talk ("suits you", "ties it together",
    /// "short and sweet") are deliberately left out to avoid rejecting good explanations.
    static let garmentWords: Set<String> = [
        "jacket", "blazer", "coat", "parka", "cardigan", "sweater", "jumper", "hoodie", "sweatshirt", "vest",
        "belt", "necktie", "scarf", "hat", "cap", "bag", "sock", "glove", "sunglasses", "jewelry", "necklace",
        "boot", "sneaker", "trainer", "loafer", "oxford", "heel", "sandal", "slipper", "brogue", "derby",
        "skirt", "dress", "jean", "chino", "trouser", "jogger", "legging",
        "shirt", "tee", "polo", "blouse",
    ]

    /// Fabric claims can't be made from a photo.
    static let materialWords: Set<String> = [
        "cotton", "linen", "wool", "leather", "suede", "silk", "denim", "cashmere", "polyester", "velvet", "corduroy", "tweed", "satin",
    ]

    /// Phrases that change the outfit rather than explain it.
    static let changePhrases = [
        "swap", "instead of", "you could also", "consider adding", "try adding", "add a", "add an", "pair it with a", "layer",
    ]

    /// Generic words for each role that never introduce a new piece.
    private static func genericWords(for category: ClothingCategory) -> Set<String> {
        switch category {
        case .tops: ["top", "shirt"]
        case .bottoms: ["pant", "trouser", "bottom"]
        case .shoes: ["shoe", "footwear"]
        case .dresses: ["dress"]
        case .outerwear: ["layer", "jacket", "coat"]
        default: []
        }
    }

    /// Returns the cleaned explanation, or nil if it breaks a rule.
    static func validated(_ raw: String, for input: OutfitExplanationInput, otherItemNames: [String]) -> String? {
        var text = raw
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"“”' ").union(.whitespaces))
        while text.contains("  ") { text = text.replacingOccurrences(of: "  ", with: " ") }
        guard !text.isEmpty, text.count <= maxLength else { return nil }
        if let last = text.last, !".!?".contains(last) { text += "." }

        let lower = text.lowercased()
        if lower.contains(where: { "$€£¥".contains($0) }) { return nil }
        // With a suggested layer, "add the jacket" or "layer it" describes the app's own choice.
        let layerPhrases: Set<String> = ["add a", "add an", "layer"]
        let phrases = input.hasLayer ? changePhrases.filter { !layerPhrases.contains($0) } : changePhrases
        if phrases.contains(where: { lower.contains($0) }) { return nil }

        // Words the outfit itself justifies.
        var allowed = Set<String>()
        for piece in input.pieces {
            allowed.formUnion(words(in: piece.name))
            allowed.formUnion(genericWords(for: piece.category))
        }

        for word in words(in: text) where !allowed.contains(word) {
            if garmentWords.contains(word) || materialWords.contains(word) { return nil }
        }

        // Never name something else from the closet.
        let outfitNames = Set(input.pieces.map { $0.name.lowercased() })
        for name in otherItemNames.map({ $0.lowercased() }) where name.count > 3 && !outfitNames.contains(name) {
            if lower.contains(name) { return nil }
        }
        return text
    }

    /// Lowercased letter-only words with a trailing plural "s" removed, so "loafers" matches "loafer".
    static func words(in text: String) -> Set<String> {
        let tokens = text.lowercased().split { !$0.isLetter }.map(String.init)
        return Set(tokens.map { $0.count > 3 && $0.hasSuffix("s") && !$0.hasSuffix("ss") ? String($0.dropLast()) : $0 })
    }
}
