import Foundation

/// Deterministic statistics about the wardrobe and how it's used. No AI involved.
struct WardrobeInsights: Sendable {
    struct CategoryCount: Equatable, Sendable {
        let category: ClothingCategory
        let count: Int
    }

    struct ColorCount: Equatable, Sendable {
        let color: ClothingColor
        let count: Int
        /// Share of all items, 0...1.
        let share: Double
    }

    struct Usage: Equatable, Sendable {
        let item: ClothingItem
        let timesWorn: Int
        let lastWorn: Date?
    }

    struct Versatility: Equatable, Sendable {
        let item: ClothingItem
        /// How many tops and dresses this piece appears with in suggestions.
        let matchingStarts: Int
        let totalStarts: Int
    }

    struct Gap: Equatable, Sendable {
        let item: ClothingItem
        let reason: String
    }

    let totalItems: Int
    let categories: [CategoryCount]
    let colors: [ColorCount]
    /// True once at least one outfit has been logged as worn.
    let hasWearHistory: Bool
    let mostWorn: [Usage]
    let notWornLately: [Usage]
    let versatile: [Versatility]
    let needsMatch: [Gap]

    /// Items not worn for this many days count as "not worn lately".
    static let notWornDays = 30
    /// Items added this recently are left out of "not worn lately".
    static let newItemGraceDays = 14

    static func compute(
        items: [ClothingItem],
        outfits: [Outfit],
        now: Date = .now,
        calendar: Calendar = .current,
        listLimit: Int = 5
    ) -> WardrobeInsights {
        // Counts
        let categories = ClothingCategory.allCases
            .map { category in CategoryCount(category: category, count: items.filter { $0.category == category }.count) }
            .filter { $0.count > 0 }
            .sorted { $0.count != $1.count ? $0.count > $1.count : order(of: $0.category) < order(of: $1.category) }

        let colorCounts = Dictionary(grouping: items, by: \.primaryColor).mapValues(\.count)
        let colors = colorCounts
            .map { ColorCount(color: $0.key, count: $0.value, share: Double($0.value) / Double(max(items.count, 1))) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.color.rawValue < $1.color.rawValue }
            .prefix(6)
            .map { $0 }

        // Wear history: only core pieces count, because optional extras may not have been worn.
        var timesWorn: [UUID: Int] = [:]
        var lastWorn: [UUID: Date] = [:]
        for outfit in outfits where !outfit.wornDates.isEmpty {
            for id in outfit.key.itemIDs {
                timesWorn[id, default: 0] += outfit.timesWorn
                if let date = outfit.lastWorn, lastWorn[id].map({ date > $0 }) ?? true { lastWorn[id] = date }
            }
        }
        let hasWearHistory = !timesWorn.isEmpty
        let usage = items.map { Usage(item: $0, timesWorn: timesWorn[$0.id] ?? 0, lastWorn: lastWorn[$0.id]) }

        let mostWorn = usage
            .filter { $0.timesWorn > 0 }
            .sorted { $0.timesWorn != $1.timesWorn ? $0.timesWorn > $1.timesWorn : $0.item.name < $1.item.name }
            .prefix(listLimit)
            .map { $0 }

        let wearable: Set<ClothingCategory> = [.tops, .bottoms, .dresses, .shoes]
        let cutoff = calendar.date(byAdding: .day, value: -notWornDays, to: now) ?? now
        let graceCutoff = calendar.date(byAdding: .day, value: -newItemGraceDays, to: now) ?? now
        let notWornLately: [Usage] = hasWearHistory ? usage
            .filter { wearable.contains($0.item.category) && $0.item.dateAdded <= graceCutoff }
            .filter { ($0.lastWorn ?? .distantPast) < cutoff }
            .sorted { ($0.lastWorn ?? .distantPast) < ($1.lastWorn ?? .distantPast) }
            .prefix(listLimit * 2)
            .map { $0 } : []

        // Versatility and gaps use the matcher's own scoring, so they agree with suggestions.
        // A piece "goes with" a start if any combination including it clears the quality bar,
        // regardless of the variety cap that limits how often it's shown in one list.
        let starts = items.filter { OutfitMatcher.startingCategories.contains($0.category) }
        let allBottoms = items.filter { $0.category == .bottoms }
        let allShoes = items.filter { $0.category == .shoes }
        var appearances: [UUID: Set<UUID>] = [:]
        for start in starts {
            let bottomOptions: [ClothingItem?] = start.category == .dresses ? [nil] : allBottoms.map { $0 }
            for bottom in bottomOptions {
                for shoe in allShoes {
                    guard let s = OutfitMatcher.evaluate(top: start, bottom: bottom, shoes: shoe),
                          s.score >= OutfitMatcher.minimumScore else { continue }
                    for id in [bottom?.id, shoe.id].compactMap({ $0 }) {
                        appearances[id, default: []].insert(start.id)
                    }
                }
            }
        }

        var gaps: [Gap] = []
        for start in starts {
            switch OutfitMatcher.match(top: start, wardrobe: items) {
            case .suggestions:
                break
            case .missingPieces(let needsBottoms, let needsShoes):
                let missing = [needsBottoms ? "pants" : nil, needsShoes ? "shoes" : nil].compactMap { $0 }
                gaps.append(Gap(item: start, reason: "Add \(missing.joined(separator: " and ")) to match it"))
            case .noGoodMatches:
                gaps.append(Gap(item: start, reason: gapReason(for: start, in: items)))
            case .allHidden:
                break
            }
        }

        let versatile = items
            .filter { $0.category == .bottoms || $0.category == .shoes }
            .compactMap { item -> Versatility? in
                let count = appearances[item.id]?.count ?? 0
                return count > 0 ? Versatility(item: item, matchingStarts: count, totalStarts: starts.count) : nil
            }
            .sorted { $0.matchingStarts != $1.matchingStarts ? $0.matchingStarts > $1.matchingStarts : $0.item.name < $1.item.name }
            .prefix(listLimit)
            .map { $0 }

        return WardrobeInsights(
            totalItems: items.count,
            categories: categories,
            colors: colors,
            hasWearHistory: hasWearHistory,
            mostWorn: mostWorn,
            notWornLately: notWornLately,
            versatile: versatile,
            needsMatch: gaps.sorted { $0.item.name < $1.item.name }
        )
    }

    /// Explains why nothing matches: usually no shoes (or pants) at a compatible dress level.
    private static func gapReason(for start: ClothingItem, in items: [ClothingItem]) -> String {
        let style = start.formality.displayName.lowercased()
        let compatible: (ClothingItem) -> Bool = { abs(level($0.formality) - level(start.formality)) <= 1 }
        let shoes = items.filter { $0.category == .shoes }
        if !shoes.contains(where: compatible) {
            return "None of your shoes suit its \(style) style"
        }
        if start.category == .tops {
            let bottoms = items.filter { $0.category == .bottoms }
            if !bottoms.contains(where: compatible) {
                return "None of your pants suit its \(style) style"
            }
        }
        return "Its \(start.primaryColor.displayName.lowercased()) doesn't go with your pants and shoes"
    }

    private static func level(_ formality: Formality) -> Int {
        switch formality {
        case .casual: 0
        case .smartCasual: 1
        case .formal: 2
        }
    }

    private static func order(of category: ClothingCategory) -> Int {
        ClothingCategory.allCases.firstIndex(of: category) ?? 0
    }
}
