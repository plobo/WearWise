import Foundation

/// Identifies one core combination: a top + pants + shoes, or a dress + shoes.
/// The optional outer layer is not part of the key, so adding a jacket later keeps saved state.
struct OutfitKey: Hashable, Sendable {
    /// The starting piece: a top or a dress.
    let topID: UUID
    /// Nil for dress outfits.
    let bottomID: UUID?
    let shoesID: UUID

    var itemIDs: [UUID] { [topID, bottomID, shoesID].compactMap { $0 } }

    func contains(_ itemID: UUID) -> Bool { itemIDs.contains(itemID) }
}

/// A combination the user has interacted with: saved, hidden, or worn.
struct Outfit: Identifiable, Hashable, Sendable {
    let id: UUID
    let key: OutfitKey
    /// Outer layer shown with the outfit when it was saved or worn.
    var layerID: UUID?
    var isSaved: Bool
    /// "Not for me": never suggested again until restored.
    var isHidden: Bool
    /// One entry per day worn, oldest first.
    var wornDates: [Date]
    let dateCreated: Date

    var lastWorn: Date? { wornDates.max() }
    var timesWorn: Int { wornDates.count }

    /// A record with no saved, hidden or worn state carries no information and can be dropped.
    var isEmpty: Bool { !isSaved && !isHidden && wornDates.isEmpty }
}

/// Persistence boundary for outfits. Items are referenced by ID only.
@MainActor
protocol OutfitRepository: AnyObject {
    func allOutfits() throws -> [Outfit]
    func insert(_ outfit: Outfit) throws
    func update(_ outfit: Outfit) throws
    func delete(id: UUID) throws
    /// Deletes outfits whose core pieces include the item, and clears it where it was only the layer.
    func deleteOutfits(containing itemID: UUID) throws
}

/// Inputs from the user's history that shape suggestions.
struct MatchContext: Sendable {
    var hidden: Set<OutfitKey> = []
    /// Most recent day each item was worn.
    var lastWorn: [UUID: Date] = [:]
    var now: Date = .now
    var calendar: Calendar = .current

    /// Whole days between the day an item was last worn and today, or nil if never worn.
    func daysSinceWorn(_ itemID: UUID) -> Int? {
        guard let date = lastWorn[itemID] else { return nil }
        let from = calendar.startOfDay(for: date)
        let to = calendar.startOfDay(for: now)
        return calendar.dateComponents([.day], from: from, to: to).day
    }

    static func lastWorn(from outfits: [Outfit]) -> [UUID: Date] {
        var result: [UUID: Date] = [:]
        for outfit in outfits {
            guard let date = outfit.lastWorn else { continue }
            for id in outfit.key.itemIDs where result[id].map({ date > $0 }) ?? true {
                result[id] = date
            }
        }
        return result
    }
}
