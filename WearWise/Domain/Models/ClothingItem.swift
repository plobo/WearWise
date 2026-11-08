import Foundation

/// Where an item's attributes came from. AI output is never treated as a verified fact.
enum AIAnalysisStatus: String, Sendable, Codable {
    /// Entered by hand, no analysis ran.
    case manual
    /// User saved the suggestion without changing it.
    case suggestedAccepted
    /// User corrected at least one suggested value.
    case suggestedEdited
    /// Analysis couldn't run (AI off / unsupported device) and the user filled it in.
    case analysisUnavailable
    /// Analysis failed and the user filled it in.
    case analysisFailed
}

/// A confirmed wardrobe item. The wardrobe database is the source of truth.
struct ClothingItem: Identifiable, Sendable, Hashable {
    let id: UUID
    var name: String
    var category: ClothingCategory
    var primaryColor: ClothingColor
    var secondaryColors: [ClothingColor]
    var pattern: ClothingPattern
    var formality: Formality
    var isFavorite: Bool
    var imagePath: String
    var thumbnailPath: String
    var dateAdded: Date
    var dateModified: Date
    var aiStatus: AIAnalysisStatus

    var colorDescription: String {
        ([primaryColor] + secondaryColors).map(\.displayName).joined(separator: ", ")
    }
}

/// Editable form state for adding or editing an item. Optional fields must be confirmed before saving.
struct ClothingDraft: Equatable, Sendable {
    var name: String = ""
    var category: ClothingCategory?
    var primaryColor: ClothingColor?
    var secondaryColors: [ClothingColor] = []
    var pattern: ClothingPattern = .unknown
    var formality: Formality?

    init() {}

    init(item: ClothingItem) {
        name = item.name
        category = item.category
        primaryColor = item.primaryColor
        secondaryColors = item.secondaryColors
        pattern = item.pattern
        formality = item.formality
    }

    init(analysis: ClothingAnalysis) {
        name = analysis.name
        category = analysis.category
        primaryColor = analysis.colors.first?.color
        secondaryColors = Array(analysis.colors.dropFirst().map(\.color).prefix(2))
        pattern = analysis.pattern
        formality = analysis.formality
    }

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Human-readable list of what still needs filling in.
    var missingFields: [String] {
        var missing: [String] = []
        if trimmedName.isEmpty { missing.append("name") }
        if category == nil { missing.append("category") }
        if primaryColor == nil { missing.append("main colour") }
        if formality == nil { missing.append("casual or formal") }
        return missing
    }

    var isComplete: Bool { missingFields.isEmpty }

    /// Secondary colours never repeat the primary colour.
    var normalizedSecondaryColors: [ClothingColor] {
        var seen: Set<ClothingColor> = primaryColor.map { [$0] } ?? []
        return secondaryColors.filter { seen.insert($0).inserted }
    }

    /// Status for a new item given whether there was a suggestion and how analysis went.
    static func status(
        for draft: ClothingDraft,
        suggestion: ClothingDraft?,
        analysisFailure: AIAnalysisStatus?
    ) -> AIAnalysisStatus {
        if let suggestion {
            return draft == suggestion ? .suggestedAccepted : .suggestedEdited
        }
        return analysisFailure ?? .manual
    }
}
