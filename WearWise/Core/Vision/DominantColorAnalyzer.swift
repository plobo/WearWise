import CoreGraphics
import Foundation

/// Estimates garment colours by sampling pixels.
///
/// Assumes the garment is roughly centred. Colours that dominate the outer border
/// are treated as background and down-weighted in the centre region.
enum DominantColorAnalyzer {
    struct RGB: Sendable, Equatable {
        let r: Double, g: Double, b: Double
    }

    static let sampleSize = 48

    static func dominantColors(in image: CGImage, minimumShare: Double = 0.1) -> [ColorShare] {
        guard let pixels = downsample(image, to: sampleSize) else { return [] }
        return dominantColors(pixels: pixels, width: sampleSize, height: sampleSize, minimumShare: minimumShare)
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
        let total = weighted.values.reduce(0, +)
        guard total > 0 else { return [] }

        return weighted
            .map { ColorShare(color: $0.key, share: $0.value / total) }
            .filter { $0.share >= minimumShare }
            .sorted { $0.share > $1.share }
            .prefix(3)
            .map { $0 }
    }

    private static func downsample(_ image: CGImage, to side: Int) -> [RGB]? {
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
            RGB(r: Double(data[$0]) / 255, g: Double(data[$0 + 1]) / 255, b: Double(data[$0 + 2]) / 255)
        }
    }
}
