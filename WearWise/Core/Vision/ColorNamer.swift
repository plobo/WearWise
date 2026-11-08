import Foundation

/// Maps an sRGB colour to the app's controlled colour vocabulary using HSB rules.
enum ColorNamer {
    /// Components are 0...1.
    static func name(red r: Double, green g: Double, blue b: Double) -> ClothingColor {
        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        let brightness = maxC
        let delta = maxC - minC
        let saturation = maxC == 0 ? 0 : delta / maxC

        // Achromatic
        if brightness < 0.18 { return .black }
        if saturation < 0.14 || delta < 0.06 {
            if brightness > 0.85 { return .white }
            if brightness < 0.28 { return .black }
            return .grey
        }

        var hue: Double
        if maxC == r {
            hue = 60 * ((g - b) / delta).truncatingRemainder(dividingBy: 6)
        } else if maxC == g {
            hue = 60 * ((b - r) / delta + 2)
        } else {
            hue = 60 * ((r - g) / delta + 4)
        }
        if hue < 0 { hue += 360 }

        switch hue {
        case 0..<15, 345...360:
            if brightness < 0.55 { return .burgundy }
            if saturation < 0.45 && brightness > 0.75 { return .pink }
            return .red
        case 15..<45:
            if saturation < 0.38 && brightness > 0.6 { return .beige }
            if brightness < 0.62 { return .brown }
            return .orange
        case 45..<70:
            if saturation < 0.38 && brightness > 0.6 { return .beige }
            if brightness < 0.55 { return .olive }
            return .yellow
        case 70..<170:
            if brightness < 0.5 && saturation < 0.6 { return .olive }
            return .green
        case 170..<255:
            if brightness < 0.45 { return .navy }
            if saturation < 0.45 && brightness > 0.6 { return .lightBlue }
            return .blue
        case 255..<300:
            return .purple
        default: // 300..<345
            if brightness < 0.5 { return .burgundy }
            return .pink
        }
    }
}
