import CoreGraphics
import Foundation
import UIKit

enum ImageProcessingError: LocalizedError {
    case unreadableImage

    var errorDescription: String? {
        "This photo couldn't be read. Try a different image."
    }
}

/// Decodes, orientation-normalises and resizes photos off the main thread.
struct ImageProcessor: Sendable {
    var maxDimension: CGFloat = 1024
    var thumbnailDimension: CGFloat = 400

    struct Prepared: @unchecked Sendable {
        /// Upright, resized image for analysis.
        let cgImage: CGImage
        /// JPEG of the same image for local storage.
        let jpegData: Data
        /// Small JPEG for grids.
        let thumbnailData: Data
    }

    @concurrent
    func prepare(_ data: Data) async throws -> Prepared {
        guard let source = UIImage(data: data), source.size.width > 0, source.size.height > 0 else {
            throw ImageProcessingError.unreadableImage
        }
        let full = Self.render(source, maxDimension: maxDimension)
        let thumb = Self.render(source, maxDimension: thumbnailDimension)
        guard let cgImage = full.cgImage,
              let jpeg = full.jpegData(compressionQuality: 0.85),
              let thumbJPEG = thumb.jpegData(compressionQuality: 0.8)
        else {
            throw ImageProcessingError.unreadableImage
        }
        return Prepared(cgImage: cgImage, jpegData: jpeg, thumbnailData: thumbJPEG)
    }

    /// Drawing a UIImage applies its EXIF orientation, so the output is upright.
    private static func render(_ source: UIImage, maxDimension: CGFloat) -> UIImage {
        let scale = min(1, maxDimension / max(source.size.width, source.size.height))
        let target = CGSize(width: (source.size.width * scale).rounded(), height: (source.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            source.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
