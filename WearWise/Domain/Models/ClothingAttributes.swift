import Foundation

/// Stable wardrobe categories used by application logic.
enum ClothingCategory: String, CaseIterable, Sendable, Codable {
    case tops, bottoms, dresses, outerwear, shoes, accessories, activewear, other

    var displayName: String { rawValue.capitalized }
}

/// What kind of accessory an item is. Drives accessory rules (a belt matches the shoes).
enum AccessoryKind: String, CaseIterable, Sendable, Codable {
    case belt, bag, scarf, hat, watch, jewelry, other

    var displayName: String {
        switch self {
        case .jewelry: "Jewellery"
        default: rawValue.capitalized
        }
    }

    private static let keywords: [(AccessoryKind, [String])] = [
        (.belt, ["belt"]),
        (.bag, ["bag", "handbag", "backpack", "tote", "purse", "clutch", "satchel"]),
        (.scarf, ["scarf", "shawl", "stole"]),
        (.hat, ["hat", "cap", "beanie", "beret", "fedora"]),
        (.watch, ["watch"]),
        (.jewelry, ["necklace", "bracelet", "ring", "earring", "jewelry", "jewellery", "pendant", "brooch"]),
    ]

    /// Guesses the kind from a name or classifier labels ("Brown leather belt" → belt). Nil if nothing matches.
    static func infer(from texts: [String]) -> AccessoryKind? {
        for text in texts {
            let words = Set(text.lowercased().split { !$0.isLetter }.map { word -> String in
                word.count > 3 && word.hasSuffix("s") ? String(word.dropLast()) : String(word)
            })
            for (kind, keys) in keywords where keys.contains(where: words.contains) {
                return kind
            }
        }
        return nil
    }
}

/// How dressy an item is. Central to outfit matching later on.
enum Formality: String, CaseIterable, Sendable, Codable {
    case casual, smartCasual, formal

    var displayName: String {
        switch self {
        case .casual: "Casual"
        case .smartCasual: "Smart casual"
        case .formal: "Formal"
        }
    }
}

enum ClothingPattern: String, CaseIterable, Sendable, Codable {
    case solid, striped, checked, floral, printed, other, unknown

    var displayName: String { rawValue.capitalized }
}

/// Controlled colour vocabulary. Colours are measured from pixels, not guessed by the model.
enum ClothingColor: String, CaseIterable, Sendable, Codable {
    case black, white, grey, navy, blue, lightBlue, green, olive, yellow,
         orange, red, burgundy, pink, purple, beige, brown

    var displayName: String {
        switch self {
        case .lightBlue: "Light blue"
        default: rawValue.capitalized
        }
    }

    /// Representative sRGB value (0...1) for swatches.
    var swatch: (red: Double, green: Double, blue: Double) {
        switch self {
        case .black: (0.08, 0.08, 0.08)
        case .white: (0.97, 0.97, 0.97)
        case .grey: (0.55, 0.55, 0.55)
        case .navy: (0.12, 0.16, 0.33)
        case .blue: (0.15, 0.35, 0.75)
        case .lightBlue: (0.62, 0.74, 0.88)
        case .green: (0.18, 0.55, 0.30)
        case .olive: (0.42, 0.42, 0.20)
        case .yellow: (0.95, 0.85, 0.25)
        case .orange: (0.93, 0.52, 0.18)
        case .red: (0.80, 0.15, 0.15)
        case .burgundy: (0.45, 0.10, 0.17)
        case .pink: (0.93, 0.62, 0.72)
        case .purple: (0.48, 0.28, 0.62)
        case .beige: (0.84, 0.76, 0.62)
        case .brown: (0.45, 0.29, 0.17)
        }
    }
}

/// A measured colour and the share of the garment area it covers.
struct ColorShare: Sendable, Equatable {
    let color: ClothingColor
    let share: Double
}

/// What Vision saw in the photo.
struct VisionLabel: Sendable, Equatable {
    let identifier: String
    let confidence: Double
}

/// Combined, unconfirmed suggestion for one clothing photo.
/// Nothing here is a verified fact until the user confirms it.
struct ClothingAnalysis: Sendable, Equatable {
    enum Source: Sendable, Equatable {
        /// Foundation Models interpreted the Vision + colour evidence.
        case onDeviceModel
        /// Deterministic fallback from Vision labels only.
        case visionOnly(reason: String)
    }

    var name: String
    var category: ClothingCategory
    var pattern: ClothingPattern
    var formality: Formality?
    var colors: [ColorShare]
    var visionLabels: [VisionLabel]
    var source: Source
}
