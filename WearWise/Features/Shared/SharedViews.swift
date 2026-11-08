import SwiftUI
import UIKit

enum Theme {
    static let accent = Color(red: 0.55, green: 0.38, blue: 0.27)
    static let cardBackground = Color(.secondarySystemBackground)
    static let cornerRadius: CGFloat = 14
    /// Secondary text with enough contrast on both the page and card backgrounds (WCAG AA).
    static let secondaryText = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.78, alpha: 1)
            : UIColor(white: 0.32, alpha: 1)
    })
    /// Warm ivory behind background-removed items.
    static let cutoutBackground = Color(red: 0.96, green: 0.94, blue: 0.90)
}

/// Shows an item's thumbnail. Cut-outs are fitted on ivory; photos fill the frame.
struct ItemThumbnail: View {
    let item: ClothingItem
    var padding: CGFloat = 10

    var body: some View {
        if item.cutoutPath != nil {
            Theme.cutoutBackground
                .overlay {
                    StoredImage(path: item.thumbnailPath, contentMode: .fit, background: Theme.cutoutBackground)
                        .padding(padding)
                }
        } else {
            StoredImage(path: item.thumbnailPath)
        }
    }
}

/// Loads a locally stored photo off the main thread.
struct StoredImage: View {
    let path: String
    var contentMode: ContentMode = .fill
    var background: Color = Theme.cardBackground

    @Environment(WardrobeStore.self) private var wardrobe
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            Rectangle().fill(background)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if failed {
                Image(systemName: "photo")
                    .font(.title)
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityLabel("Photo missing")
            }
        }
        .clipped()
        .task(id: path) {
            image = await Self.load(wardrobe.imageStore.url(for: path))
            failed = image == nil
        }
    }

    @concurrent
    private static func load(_ url: URL) async -> UIImage? {
        guard let image = UIImage(contentsOfFile: url.path(percentEncoded: false)) else { return nil }
        return await image.byPreparingForDisplay() ?? image
    }
}

struct ColorSwatch: View {
    let color: ClothingColor
    var size: CGFloat = 14

    var body: some View {
        Circle()
            .fill(Color(red: color.swatch.red, green: color.swatch.green, blue: color.swatch.blue))
            .overlay(Circle().stroke(.secondary.opacity(0.5), lineWidth: 0.5))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct ClothingCard: View {
    let item: ClothingItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // A fixed-ratio frame with the photo overlaid, so a filled image can't widen the grid cell.
            Color.clear
                .aspectRatio(3 / 4, contentMode: .fit)
                .overlay { ItemThumbnail(item: item) }
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
                .overlay(alignment: .topTrailing) {
                    if item.isFavorite {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.white)
                            .shadow(radius: 2)
                            .padding(8)
                    }
                }
            Text(item.name)
                .font(.subheadline.weight(.medium))
            HStack(spacing: 4) {
                ColorSwatch(color: item.primaryColor, size: 10)
                Text("\(item.category.displayName) · \(item.formality.displayName)")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.name), \(item.primaryColor.displayName) \(item.category.displayName), \(item.formality.displayName)\(item.isFavorite ? ", favourite" : "")")
    }
}

/// Editable attribute fields shared by Add and Edit. A sparkle marks values that still match the AI suggestion.
struct ClothingFormFields: View {
    @Binding var draft: ClothingDraft
    var suggestion: ClothingDraft?

    var body: some View {
        Section {
            HStack {
                TextField("Name", text: $draft.name)
                    .textInputAutocapitalization(.sentences)
                suggestedMark(suggestion.map { $0.name == draft.name && !draft.name.isEmpty } ?? false)
            }
            Picker(selection: $draft.category) {
                Text("Choose…").tag(ClothingCategory?.none)
                ForEach(ClothingCategory.allCases, id: \.self) { Text($0.displayName).tag(Optional($0)) }
            } label: {
                labelText("Category", suggested: suggestion?.category != nil && suggestion?.category == draft.category)
            }
            if draft.category == .accessories {
                Picker("Type", selection: $draft.accessoryKind) {
                    Text("Not set").tag(AccessoryKind?.none)
                    ForEach(AccessoryKind.allCases, id: \.self) { Text($0.displayName).tag(Optional($0)) }
                }
            }
            Picker(selection: $draft.formality) {
                Text("Choose…").tag(Formality?.none)
                ForEach(Formality.allCases, id: \.self) { Text($0.displayName).tag(Optional($0)) }
            } label: {
                labelText("Casual or formal", suggested: suggestion?.formality != nil && suggestion?.formality == draft.formality)
            }
        } header: {
            Text("Item")
        }

        Section {
            Picker(selection: $draft.primaryColor) {
                Text("Choose…").tag(ClothingColor?.none)
                ForEach(ClothingColor.allCases, id: \.self) { color in
                    Label { Text(color.displayName) } icon: { ColorSwatch(color: color) }
                        .tag(Optional(color))
                }
            } label: {
                labelText("Main colour", suggested: suggestion?.primaryColor != nil && suggestion?.primaryColor == draft.primaryColor)
            }
            NavigationLink {
                SecondaryColorPicker(selection: $draft.secondaryColors, excluding: draft.primaryColor)
            } label: {
                LabeledContent("Other colours") {
                    Text(draft.normalizedSecondaryColors.isEmpty ? "None" : draft.normalizedSecondaryColors.map(\.displayName).joined(separator: ", "))
                }
            }
            Picker(selection: $draft.pattern) {
                ForEach(ClothingPattern.allCases, id: \.self) { Text($0.displayName).tag($0) }
            } label: {
                labelText("Pattern", suggested: suggestion != nil && suggestion?.pattern == draft.pattern && draft.pattern != .unknown)
            }
        } header: {
            Text("Colour and pattern")
        } footer: {
            if suggestion != nil {
                Label("Suggested values are marked with a sparkle. Check them before saving.", systemImage: "sparkles")
            }
        }
    }

    private func labelText(_ title: String, suggested: Bool) -> some View {
        HStack(spacing: 4) {
            Text(title)
            suggestedMark(suggested)
        }
    }

    @ViewBuilder
    private func suggestedMark(_ suggested: Bool) -> some View {
        if suggested {
            Image(systemName: "sparkles")
                .font(.caption)
                .foregroundStyle(Theme.accent)
                .accessibilityLabel("Suggested, not yet confirmed")
        }
    }
}

private struct SecondaryColorPicker: View {
    @Binding var selection: [ClothingColor]
    let excluding: ClothingColor?

    var body: some View {
        List(ClothingColor.allCases.filter { $0 != excluding }, id: \.self) { color in
            Button {
                if let index = selection.firstIndex(of: color) {
                    selection.remove(at: index)
                } else {
                    selection.append(color)
                }
            } label: {
                HStack {
                    ColorSwatch(color: color, size: 18)
                    Text(color.displayName).foregroundStyle(.primary)
                    Spacer()
                    if selection.contains(color) {
                        Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                    }
                }
            }
            .accessibilityAddTraits(selection.contains(color) ? .isSelected : [])
        }
        .navigationTitle("Other colours")
    }
}

/// An icon + title row for buttons inside lists and forms. Wraps cleanly at large text sizes.
struct ActionRowLabel: View {
    let title: String
    let systemImage: String

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .frame(minWidth: 24)
                .accessibilityHidden(true)
            Text(title)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
