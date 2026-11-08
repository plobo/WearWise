import CoreGraphics
import Foundation
import Vision

/// Runs Apple's built-in image classifier and returns the top labels.
struct VisionClassifier: Sendable {
    var minimumConfidence: Double = 0.1
    var maxLabels: Int = 8

    @concurrent
    func classify(_ image: CGImage) async throws -> [VisionLabel] {
        let observations = try await ClassifyImageRequest().perform(on: image)
        return observations
            .filter { Double($0.confidence) >= minimumConfidence }
            .sorted { $0.confidence > $1.confidence }
            .prefix(maxLabels)
            .map { VisionLabel(identifier: $0.identifier, confidence: Double($0.confidence)) }
    }
}

/// Deterministic category guess from Vision labels. Used when the on-device model is unavailable,
/// and as a sanity check on the model's answer.
enum VisionLabelCategoryMapper {
    private static let keywords: [(ClothingCategory, [String])] = [
        (.shoes, ["shoe", "sneaker", "boot", "sandal", "loafer", "footwear", "heel", "slipper", "cleat"]),
        (.dresses, ["dress", "gown", "skirt"]),
        (.outerwear, ["jacket", "coat", "blazer", "parka", "raincoat", "vest", "cardigan"]),
        (.bottoms, ["jeans", "trouser", "pant", "shorts", "denim", "legging", "chino"]),
        (.activewear, ["sportswear", "jersey", "tracksuit", "swimsuit", "swimwear"]),
        (.accessories, ["hat", "cap", "belt", "bag", "handbag", "backpack", "scarf", "tie", "necktie",
                        "sunglasses", "glasses", "watch", "jewelry", "necklace", "glove", "sock", "wallet"]),
        (.tops, ["shirt", "t_shirt", "tshirt", "blouse", "sweater", "hoodie", "sweatshirt", "polo", "top", "jumper"]),
    ]

    static let clothingVocabulary: Set<String> = Set(keywords.flatMap(\.1) + ["clothing", "apparel", "garment"])

    static func category(for labels: [VisionLabel]) -> ClothingCategory? {
        for label in labels.sorted(by: { $0.confidence > $1.confidence }) {
            let id = label.identifier.lowercased()
            for (category, words) in keywords where words.contains(where: { id.contains($0) }) {
                return category
            }
        }
        return nil
    }

    static func looksLikeClothing(_ labels: [VisionLabel]) -> Bool {
        labels.contains { label in
            let id = label.identifier.lowercased()
            return clothingVocabulary.contains { id.contains($0) }
        }
    }

    static func pattern(for labels: [VisionLabel]) -> ClothingPattern {
        let ids = labels.map { $0.identifier.lowercased() }
        if ids.contains(where: { $0.contains("plaid") || $0.contains("tartan") || $0.contains("check") }) { return .checked }
        if ids.contains(where: { $0.contains("stripe") }) { return .striped }
        if ids.contains(where: { $0.contains("floral") || $0.contains("flower") }) { return .floral }
        return .unknown
    }
}
