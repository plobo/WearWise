#if DEBUG
import UIKit

/// Debug-only sample data. Launch with `-seedSampleWardrobe` to fill an empty wardrobe,
/// and `-openFirstMatch` to jump straight to match results for the first top.
@MainActor
enum DebugSampleWardrobe {
    static var shouldSeed: Bool { ProcessInfo.processInfo.arguments.contains("-seedSampleWardrobe") }
    static var shouldOpenFirstMatch: Bool { ProcessInfo.processInfo.arguments.contains("-openFirstMatch") }
    static var shouldOpenOutfits: Bool { ProcessInfo.processInfo.arguments.contains("-openOutfits") }

    /// Saves the sample smart-casual outfit and logs it as worn today.
    static func seedOutfitsIfRequested(_ outfits: OutfitStore, wardrobe: WardrobeStore) {
        guard shouldSeed, outfits.outfits.isEmpty,
              let top = wardrobe.items.first(where: { $0.name == "Light blue oxford" }),
              let bottom = wardrobe.items.first(where: { $0.name == "Beige chinos" }),
              let shoes = wardrobe.items.first(where: { $0.name == "Brown loafers" })
        else { return }
        let key = OutfitKey(topID: top.id, bottomID: bottom.id, shoesID: shoes.id)
        try? outfits.toggleSaved(key)
        try? outfits.toggleWornToday(key)
    }

    static func seedIfRequested(_ wardrobe: WardrobeStore) {
        guard shouldSeed, wardrobe.items.isEmpty else { return }
        let samples: [(String, ClothingCategory, ClothingColor, Formality, String)] = [
            ("Black oxfords", .shoes, .black, .formal, "shoe"),
            ("White sneakers", .shoes, .white, .casual, "shoe"),
            ("Brown loafers", .shoes, .brown, .smartCasual, "shoe"),
            ("Grey trousers", .bottoms, .grey, .formal, "figure.walk"),
            ("Dark jeans", .bottoms, .navy, .casual, "figure.walk"),
            ("Beige chinos", .bottoms, .beige, .smartCasual, "figure.walk"),
            ("White tee", .tops, .white, .casual, "tshirt"),
            ("Light blue oxford", .tops, .lightBlue, .smartCasual, "tshirt"),
        ]
        for (name, category, color, formality, symbol) in samples {
            var draft = ClothingDraft()
            draft.name = name
            draft.category = category
            draft.primaryColor = color
            draft.formality = formality
            draft.pattern = .solid
            _ = try? wardrobe.add(draft, photo: photo(color: color, symbol: symbol), status: .manual)
        }
    }

    private static func photo(color: ClothingColor, symbol: String) -> ImageProcessor.Prepared {
        let size = CGSize(width: 400, height: 400)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor(red: 0.96, green: 0.94, blue: 0.9, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let config = UIImage.SymbolConfiguration(pointSize: 220, weight: .regular)
            let tint = UIColor(red: color.swatch.red, green: color.swatch.green, blue: color.swatch.blue, alpha: 1)
            if let glyph = UIImage(systemName: symbol + ".fill", withConfiguration: config) ?? UIImage(systemName: symbol, withConfiguration: config) {
                let rendered = glyph.withTintColor(tint, renderingMode: .alwaysOriginal)
                let origin = CGPoint(x: (size.width - rendered.size.width) / 2, y: (size.height - rendered.size.height) / 2)
                rendered.draw(at: origin)
            }
        }
        let data = image.jpegData(compressionQuality: 0.85)!
        return ImageProcessor.Prepared(cgImage: image.cgImage!, jpegData: data, thumbnailData: data)
    }
}
#endif
