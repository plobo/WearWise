import Foundation

/// Identifies one top + pants + shoes combination.
struct OutfitKey: Hashable, Sendable {
    let topID: UUID
    let bottomID: UUID
    let shoesID: UUID

    var itemIDs: [UUID] { [topID, bottomID, shoesID] }

    func contains(_ itemID: UUID) -> Bool { itemIDs.contains(itemID) }
}

/// A combination the user has interacted with: saved, hidden, or worn.
struct Outfit: Identifiable, Hashable, Sendable {
    let id: UUID
    let key: OutfitKey
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
