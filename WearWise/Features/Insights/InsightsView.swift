import SwiftUI

/// What's in the wardrobe, what works hardest, what's missing, and what's worn.
struct InsightsView: View {
    @Environment(WardrobeStore.self) private var wardrobe
    @Environment(OutfitStore.self) private var outfits

    var body: some View {
        NavigationStack {
            Group {
                if wardrobe.items.isEmpty {
                    ContentUnavailableView(
                        "No insights yet",
                        systemImage: "chart.bar",
                        description: Text("Add clothes to your wardrobe to see what you have, what goes with the most, and what's missing.")
                    )
                } else {
                    content(WardrobeInsights.compute(items: wardrobe.items, outfits: outfits.outfits))
                }
            }
            .navigationTitle("Insights")
            .navigationDestination(for: UUID.self) { ClothingDetailView(itemID: $0) }
        }
    }

    private func content(_ insights: WardrobeInsights) -> some View {
        List {
            if !insights.versatile.isEmpty {
                Section {
                    ForEach(insights.versatile, id: \.item.id) { entry in
                        itemRow(entry.item, detail: "Goes with \(entry.matchingStarts) of \(entry.totalStarts) tops and dresses")
                    }
                } header: {
                    Text("Most versatile")
                } footer: {
                    Text("Pants and shoes that appear in the most suggestions.")
                }
            }

            if !insights.needsMatch.isEmpty {
                Section {
                    ForEach(insights.needsMatch, id: \.item.id) { gap in
                        itemRow(gap.item, detail: gap.reason)
                    }
                } header: {
                    Text("Needs a match")
                } footer: {
                    Text("Tops and dresses that nothing in your closet goes with yet.")
                }
            }

            Section {
                if insights.hasWearHistory {
                    ForEach(insights.mostWorn, id: \.item.id) { usage in
                        itemRow(usage.item, detail: usage.timesWorn == 1 ? "Worn once" : "Worn \(usage.timesWorn) times")
                    }
                } else {
                    Text("Tap Wore today on an outfit in Match to start tracking what you wear.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
            } header: {
                Text("Most worn")
            }

            if insights.hasWearHistory, !insights.notWornLately.isEmpty {
                Section {
                    ForEach(insights.notWornLately, id: \.item.id) { usage in
                        itemRow(usage.item, detail: usage.lastWorn.map { "Last worn \($0.formatted(.relative(presentation: .named)))" } ?? "Not worn yet")
                    }
                } header: {
                    Text("Not worn lately")
                } footer: {
                    Text("Not logged as worn in the last \(WardrobeInsights.notWornDays) days. Items added in the last \(WardrobeInsights.newItemGraceDays) days aren't included.")
                }
            }
            Section {
                LabeledContent("Items", value: "\(insights.totalItems)")
                ForEach(insights.categories, id: \.category) { entry in
                    LabeledContent(entry.category.displayName, value: "\(entry.count)")
                }
            } header: {
                Text("Your wardrobe")
            }

            Section {
                ForEach(insights.colors, id: \.color) { entry in
                    HStack(spacing: 10) {
                        ColorSwatch(color: entry.color, size: 18)
                        Text(entry.color.displayName)
                        Spacer()
                        Text("\(entry.count) · \(entry.share.formatted(.percent.precision(.fractionLength(0))))")
                            .foregroundStyle(Theme.secondaryText)
                            .monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text("Main colours")
            }

        }
    }

    private func itemRow(_ item: ClothingItem, detail: String) -> some View {
        NavigationLink(value: item.id) {
            HStack(spacing: 12) {
                ItemThumbnail(item: item, padding: 4)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).font(.subheadline.weight(.medium))
                    Text(detail).font(.caption).foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
