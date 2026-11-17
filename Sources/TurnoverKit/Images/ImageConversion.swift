import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Decodes an image with ImageIO and re-encodes it in another format.
enum ImageConversion {
    static func convert(_ source: URL, to destination: URL, as type: UTType) throws {
        guard let input = CGImageSourceCreateWithURL(source as CFURL, nil) else { throw CocoaError(.fileReadCorruptFile) }
        let index = CGImageSourceGetPrimaryImageIndex(input)
        let properties = CGImageSourceCopyPropertiesAtIndex(input, index, nil) as? [CFString: Any] ?? [:]
        guard let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              let image = uprightImage(input, at: index, longestSide: max(width, height)),
              let output = CGImageDestinationCreateWithURL(destination as CFURL, type.identifier as CFString, 1, nil)
        else { throw CocoaError(.fileReadCorruptFile) }
        CGImageDestinationAddImage(output, image, nil)
        guard CGImageDestinationFinalize(output) else { throw CocoaError(.fileWriteUnknown) }
    }

    /// The full-size image with its EXIF orientation applied to the pixels.
    /// ImageIO only applies orientation on its thumbnail path, so ask for a "thumbnail" as large
    /// as the image itself.
    private static func uprightImage(_ input: CGImageSource, at index: Int, longestSide: Int) -> CGImage? {
        CGImageSourceCreateThumbnailAtIndex(input, index, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: longestSide,
            kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary)
    }
}
