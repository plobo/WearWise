import Foundation
import Observation

/// Shared, observable outfit state: saved outfits, hidden suggestions and what was worn when.
@MainActor
@Observable
final class OutfitStore {
    private(set) var outfits: [Outfit] = []
    private(set) var loadError: String?

    private let repository: any OutfitRepository
    private let now: @MainActor () -> Date
    private let calendar: Calendar

    init(repository: any OutfitRepository, now: @escaping @MainActor () -> Date = { .now }, calendar: Calendar = .current) {
        self.repository = repository
        self.now = now
        self.calendar = calendar
        reload()
    }

    func reload() {
        do {
            outfits = try repository.allOutfits()
            loadError = nil
        } catch {
            loadError = "Your outfits couldn't be loaded."
        }
    }

    // MARK: Queries

    func outfit(for key: OutfitKey) -> Outfit? {
        outfits.first { $0.key == key }
    }

    func isSaved(_ key: OutfitKey) -> Bool { outfit(for: key)?.isSaved ?? false }

    func isWornToday(_ key: OutfitKey) -> Bool {
        outfit(for: key)?.wornDates.contains { calendar.isDate($0, inSameDayAs: now()) } ?? false
    }

    var saved: [Outfit] {
        outfits.filter(\.isSaved).sorted { $0.dateCreated > $1.dateCreated }
    }

    /// Worn outfits that aren't saved. Saved outfits show their own wear history.
    var recentlyWorn: [Outfit] {
        outfits
            .filter { !$0.wornDates.isEmpty && !$0.isSaved }
            .sorted { ($0.lastWorn ?? .distantPast) > ($1.lastWorn ?? .distantPast) }
            .prefix(10)
            .map { $0 }
    }

    var hidden: [Outfit] {
        outfits.filter(\.isHidden).sorted { $0.dateCreated > $1.dateCreated }
    }

    /// History that shapes suggestions: hidden combinations and when each item was last worn.
    func matchContext() -> MatchContext {
        MatchContext(
            hidden: Set(hidden.map(\.key)),
            lastWorn: MatchContext.lastWorn(from: outfits),
            now: now(),
            calendar: calendar
        )
    }

    // MARK: Changes

    /// - Parameter extras: The optional layer and accessories shown with the outfit, remembered when saving.
    func toggleSaved(_ key: OutfitKey, extras: OutfitExtras? = nil) throws {
        try mutate(key) { outfit in
            extras?.apply(to: &outfit)
            outfit.isSaved.toggle()
            if outfit.isSaved { outfit.isHidden = false }
        }
    }

    /// Logs today's wear, or removes it if already logged today.
    func toggleWornToday(_ key: OutfitKey, extras: OutfitExtras? = nil) throws {
        let today = now()
        try mutate(key) { outfit in
            extras?.apply(to: &outfit)
            if let index = outfit.wornDates.firstIndex(where: { calendar.isDate($0, inSameDayAs: today) }) {
                outfit.wornDates.remove(at: index)
            } else {
                outfit.wornDates.append(today)
                outfit.wornDates.sort()
                outfit.isHidden = false
            }
        }
    }

    /// "Not for me": stop suggesting this combination. Also unsaves it.
    func hide(_ key: OutfitKey) throws {
        try mutate(key) { outfit in
            outfit.isHidden = true
            outfit.isSaved = false
        }
    }

    func unhide(_ key: OutfitKey) throws {
        try mutate(key) { $0.isHidden = false }
    }

    /// Forgets an outfit entirely, including its wear history.
    func remove(_ outfit: Outfit) throws {
        try repository.delete(id: outfit.id)
        outfits.removeAll { $0.id == outfit.id }
    }

    /// Called when a clothing item is deleted, so no outfit refers to something the user no longer owns.
    func removeOutfits(containing itemID: UUID) throws {
        try repository.deleteOutfits(containing: itemID)
        outfits.removeAll { $0.key.contains(itemID) }
        for index in outfits.indices {
            if outfits[index].layerID == itemID { outfits[index].layerID = nil }
            outfits[index].accessoryIDs.removeAll { $0 == itemID }
        }
    }

    /// Creates the record on first interaction, and drops it when it no longer holds any state.
    private func mutate(_ key: OutfitKey, _ change: (inout Outfit) -> Void) throws {
        if let index = outfits.firstIndex(where: { $0.key == key }) {
            var outfit = outfits[index]
            change(&outfit)
            if outfit.isEmpty {
                try repository.delete(id: outfit.id)
                outfits.remove(at: index)
            } else {
                try repository.update(outfit)
                outfits[index] = outfit
            }
        } else {
            var outfit = Outfit(id: UUID(), key: key, isSaved: false, isHidden: false, wornDates: [], dateCreated: now())
            change(&outfit)
            guard !outfit.isEmpty else { return }
            try repository.insert(outfit)
            outfits.insert(outfit, at: 0)
        }
    }
}

/// The optional pieces shown alongside a suggestion.
struct OutfitExtras: Equatable, Sendable {
    var layerID: UUID?
    var accessoryIDs: [UUID]

    init(layerID: UUID? = nil, accessoryIDs: [UUID] = []) {
        self.layerID = layerID
        self.accessoryIDs = accessoryIDs
    }

    init(_ suggestion: OutfitSuggestion) {
        self.init(layerID: suggestion.layer?.id, accessoryIDs: suggestion.accessories.map(\.id))
    }

    func apply(to outfit: inout Outfit) {
        outfit.layerID = layerID
        outfit.accessoryIDs = accessoryIDs
    }
}

/// An outfit with its clothing resolved against the wardrobe.
struct ResolvedOutfit: Identifiable, Hashable {
    let outfit: Outfit
    let top: ClothingItem
    let bottom: ClothingItem?
    let shoes: ClothingItem
    let layer: ClothingItem?
    let accessories: [ClothingItem]

    var id: UUID { outfit.id }
    var corePieces: [ClothingItem] { [top, bottom, shoes].compactMap { $0 } }
    var extras: [ClothingItem] { [layer].compactMap { $0 } + accessories }
    var pieces: [ClothingItem] { corePieces + extras }

    /// "Beige chinos + Brown loafers", or "Black dress + Black heels" for dress outfits.
    var title: String {
        if let bottom { return "\(bottom.name) + \(shoes.name)" }
        return "\(top.name) + \(shoes.name)"
    }

    /// Returns nil if any core piece is no longer in the wardrobe, so missing clothes are never shown.
    /// Missing optional extras are simply left out.
    init?(_ outfit: Outfit, wardrobe: [ClothingItem]) {
        func find(_ id: UUID) -> ClothingItem? { wardrobe.first { $0.id == id } }
        guard let top = find(outfit.key.topID), let shoes = find(outfit.key.shoesID) else { return nil }
        var bottom: ClothingItem?
        if let bottomID = outfit.key.bottomID {
            guard let found = find(bottomID) else { return nil }
            bottom = found
        }
        self.outfit = outfit
        self.top = top
        self.bottom = bottom
        self.shoes = shoes
        layer = outfit.layerID.flatMap(find)
        accessories = outfit.accessoryIDs.compactMap(find)
    }
}
