import CoreGraphics
import Foundation

/// Estimates garment colours by sampling pixels.
///
/// Two modes:
/// - **Cut-out** (preferred): only opaque pixels of a background-removed image are counted.
/// - **Full photo** (fallback): assumes the garment is roughly centred; colours that dominate
///   the outer border are treated as background and down-weighted.
enum DominantColorAnalyzer {
    struct RGB: Sendable, Equatable {
        let r: Double, g: Double, b: Double
    }

    struct RGBA: Sendable, Equatable {
        let r: Double, g: Double, b: Double, a: Double
    }

    static let sampleSize = 48
    static let cutoutSampleSize = 64
    static let opaqueThreshold = 0.6

    // MARK: Full photo

    static func dominantColors(in image: CGImage, minimumShare: Double = 0.1) -> [ColorShare] {
        guard let pixels = downsample(image, to: sampleSize) else { return [] }
        return dominantColors(pixels: pixels.map { RGB(r: $0.r, g: $0.g, b: $0.b) }, width: sampleSize, height: sampleSize, minimumShare: minimumShare)
    }

    /// Pure, testable core. `pixels` is row-major, `width * height` long.
    static func dominantColors(
        pixels: [RGB],
        width: Int,
        height: Int,
        minimumShare: Double = 0.1
    ) -> [ColorShare] {
        guard width > 4, height > 4, pixels.count == width * height else { return [] }

        let border = max(1, min(width, height) / 10)
        var borderCounts: [ClothingColor: Int] = [:]
        var borderTotal = 0
        var centerCounts: [ClothingColor: Int] = [:]

        let x0 = width / 5, x1 = width - width / 5
        let y0 = height / 6, y1 = height - height / 6

        for y in 0..<height {
            for x in 0..<width {
                let p = pixels[y * width + x]
                let name = ColorNamer.name(red: p.r, green: p.g, blue: p.b)
                if x < border || y < border || x >= width - border || y >= height - border {
                    borderCounts[name, default: 0] += 1
                    borderTotal += 1
                } else if x >= x0, x < x1, y >= y0, y < y1 {
                    centerCounts[name, default: 0] += 1
                }
            }
        }

        // Background = a colour covering most of the border.
        let background = borderCounts
            .first { borderTotal > 0 && Double($0.value) / Double(borderTotal) > 0.6 }?
            .key

        var weighted: [ClothingColor: Double] = [:]
        for (color, count) in centerCounts {
            weighted[color] = Double(count) * (color == background ? 0.15 : 1)
        }
        return shares(from: weighted, minimumShare: minimumShare)
    }

    // MARK: Cut-out

    /// Colours of the opaque pixels of a background-removed image.
    static func dominantColors(inCutout image: CGImage, minimumShare: Double = 0.1) -> [ColorShare] {
        guard let pixels = downsample(image, to: cutoutSampleSize) else { return [] }
        return dominantColors(cutoutPixels: pixels, minimumShare: minimumShare)
    }

    /// Pure, testable core for cut-outs. Transparent pixels are ignored.
    static func dominantColors(cutoutPixels: [RGBA], minimumShare: Double = 0.1) -> [ColorShare] {
        var counts: [ClothingColor: Double] = [:]
        for p in cutoutPixels where p.a >= opaqueThreshold {
            counts[ColorNamer.name(red: p.r, green: p.g, blue: p.b), default: 0] += 1
        }
        return shares(from: counts, minimumShare: minimumShare)
    }

    /// Share of pixels that are opaque. Used to reject empty or near-empty cut-outs.
    static func opaqueFraction(in image: CGImage) -> Double {
        guard let pixels = downsample(image, to: sampleSize), !pixels.isEmpty else { return 0 }
        return Double(pixels.filter { $0.a >= opaqueThreshold }.count) / Double(pixels.count)
    }

    // MARK: Shared

    /// Shade variants of one hue. Lighting splits a single fabric colour across these.
    private static let shadeFamilies: [Set<ClothingColor>] = [
        [.navy, .blue, .lightBlue],
        [.burgundy, .red, .pink],
        [.olive, .green],
        [.black, .grey],
    ]

    /// Merges small shade variants into the main colour (e.g. shadowed navy counted as "black" stays navy
    /// only if it's in the same family), then converts counts to shares.
    static func shares(from counts: [ClothingColor: Double], minimumShare: Double) -> [ColorShare] {
        let total = counts.values.reduce(0, +)
        guard total > 0 else { return [] }

        var merged = counts
        if let primary = counts.max(by: { $0.value < $1.value || ($0.value == $1.value && $0.key.rawValue > $1.key.rawValue) })?.key,
           let family = shadeFamilies.first(where: { $0.contains(primary) }) {
            for color in family where color != primary {
                if let count = merged[color], count / total < 0.3 {
                    merged[primary, default: 0] += count
                    merged[color] = nil
                }
            }
        }

        let all: [ColorShare] = merged.map { ColorShare(color: $0.key, share: $0.value / total) }
        let kept = all.filter { $0.share >= minimumShare }.sorted(by: Self.byShare)
        return Array(kept.prefix(3))
    }

    /// Largest share first; ties broken by name so results are deterministic.
    private static func byShare(_ a: ColorShare, _ b: ColorShare) -> Bool {
        if a.share != b.share { return a.share > b.share }
        return a.color.rawValue < b.color.rawValue
    }

    /// Draws the image into a small sRGB buffer and returns un-premultiplied RGBA values.
    private static func downsample(_ image: CGImage, to side: Int) -> [RGBA]? {
        let bytesPerRow = side * 4
        var data = [UInt8](repeating: 0, count: side * bytesPerRow)
        let drawn: Bool = data.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(
                data: buffer.baseAddress,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }
        return stride(from: 0, to: data.count, by: 4).map {
            let a = Double(data[$0 + 3]) / 255
            guard a > 0 else { return RGBA(r: 0, g: 0, b: 0, a: 0) }
            return RGBA(
                r: min(1, Double(data[$0]) / 255 / a),
                g: min(1, Double(data[$0 + 1]) / 255 / a),
                b: min(1, Double(data[$0 + 2]) / 255 / a),
                a: a
            )
        }
    }
}
