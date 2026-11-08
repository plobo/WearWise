import CoreImage
import Foundation
import UIKit
import Vision

/// Abstraction so features can be tested without running Vision.
protocol ForegroundSegmenting: Sendable {
    func cutout(from image: CGImage) async throws -> ForegroundSegmenter.Cutout?
}

/// Separates the clothing item from its background using Vision foreground instance segmentation.
///
/// Returns nil when no clear subject is found. The original photo is always kept, so
/// a failed or poor cut-out never blocks adding an item.
/// Not supported in the iOS Simulator on Intel Macs ("Could not create inference context").
struct ForegroundSegmenter: ForegroundSegmenting {
    struct Cutout: @unchecked Sendable {
        /// The item cropped to its extent, with a transparent background.
        let cgImage: CGImage
        let pngData: Data
        let thumbnailPNGData: Data
    }

    var thumbnailDimension: CGFloat = 400
    /// Below this share of opaque pixels in the cropped cut-out, treat segmentation as failed.
    var minimumOpaqueFraction = 0.08

    @concurrent
    func cutout(from image: CGImage) async throws -> Cutout? {
        let handler = ImageRequestHandler(image)
        guard let observation = try await handler.perform(GenerateForegroundInstanceMaskRequest()) else { return nil }

        // Prefer the subject under the centre of the photo; fall back to every subject found.
        let centre = observation.instanceAtPoint(NormalizedPoint(x: 0.5, y: 0.5))
        let instances = centre.isEmpty ? observation.allInstances : centre
        guard !instances.isEmpty else { return nil }

        let buffer = try observation.generateMaskedImage(for: instances, imageFrom: handler, croppedToInstancesExtent: true)
        let ciImage = CIImage(cvPixelBuffer: buffer)
        guard let cgImage = CIContext().createCGImage(ciImage, from: ciImage.extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) else {
            return nil
        }
        guard DominantColorAnalyzer.opaqueFraction(in: cgImage) >= minimumOpaqueFraction else { return nil }

        let full = UIImage(cgImage: cgImage)
        guard let png = full.pngData(), let thumb = Self.thumbnail(full, maxDimension: thumbnailDimension).pngData() else {
            return nil
        }
        return Cutout(cgImage: cgImage, pngData: png, thumbnailPNGData: thumb)
    }

    private static func thumbnail(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let scale = min(1, maxDimension / max(image.size.width, image.size.height))
        let target = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
