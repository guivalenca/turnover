import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Decodes an image with ImageIO and re-encodes it in another format.
enum ImageConversion {
    /// `quality`, from 0 to 1, applies to lossy formats; nil leaves it to ImageIO.
    static func convert(_ source: URL, to destination: URL, as type: UTType, quality: Double? = nil) throws {
        guard let input = CGImageSourceCreateWithURL(source as CFURL, nil),
              CGImageSourceGetStatus(input) == .statusComplete
        else { throw ConversionError.damaged(source) }
        let index = CGImageSourceGetPrimaryImageIndex(input)
        let properties = CGImageSourceCopyPropertiesAtIndex(input, index, nil) as? [CFString: Any] ?? [:]
        guard CGImageSourceGetStatusAtIndex(input, index) == .statusComplete,
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              let image = uprightImage(input, at: index, longestSide: max(width, height))
        else { throw ConversionError.damaged(source) }
        guard let output = CGImageDestinationCreateWithURL(destination as CFURL, type.identifier as CFString, 1, nil)
        else { throw CocoaError(.fileWriteUnknown, userInfo: [NSURLErrorKey: destination]) }
        var options = metadata(from: properties, for: image)
        options[kCGImageDestinationLossyCompressionQuality] = quality
        // Formats without alpha (JPEG) composite transparent areas onto this; ImageIO documents
        // black as the default. Formats with alpha ignore it.
        options[kCGImageDestinationBackgroundColor] = CGColor(gray: 1, alpha: 1)
        CGImageDestinationAddImage(output, image, options as CFDictionary)
        guard CGImageDestinationFinalize(output) else {
            // Some formats (HEIC) decode lazily, so a truncated file only fails here.
            if image.dataProvider?.data == nil { throw ConversionError.damaged(source) }
            throw CocoaError(.fileWriteUnknown, userInfo: [NSURLErrorKey: destination])
        }
    }

    /// The metadata dictionaries worth carrying over, marked upright since the pixels now are.
    /// The colour profile travels with the image itself.
    private static func metadata(from properties: [CFString: Any], for image: CGImage) -> [CFString: Any] {
        let carried: [CFString] = [
            kCGImagePropertyExifDictionary, kCGImagePropertyExifAuxDictionary, kCGImagePropertyGPSDictionary,
            kCGImagePropertyTIFFDictionary, kCGImagePropertyIPTCDictionary, kCGImagePropertyMakerAppleDictionary,
            kCGImagePropertyDPIWidth, kCGImagePropertyDPIHeight,
        ]
        var metadata = properties.filter { carried.contains($0.key) }
        metadata[kCGImagePropertyOrientation] = 1
        if var tiff = metadata[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff[kCGImagePropertyTIFFOrientation] = 1
            metadata[kCGImagePropertyTIFFDictionary] = tiff
        }
        if var exif = metadata[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            exif[kCGImagePropertyExifPixelXDimension] = image.width
            exif[kCGImagePropertyExifPixelYDimension] = image.height
            metadata[kCGImagePropertyExifDictionary] = exif
        }
        return metadata
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
