import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Decodes an image with ImageIO and re-encodes it in another format.
enum ImageConversion {
    /// `quality`, from 0 to 1, applies to lossy formats; nil leaves it to ImageIO.
    static func convert(_ source: URL, to destination: URL, as type: UTType, quality: Double? = nil) throws {
        let decoded = try Decoded(source)
        guard let output = CGImageDestinationCreateWithURL(destination as CFURL, type.identifier as CFString, 1, nil)
        else { throw CocoaError(.fileWriteUnknown, userInfo: [NSURLErrorKey: destination]) }
        guard decoded.write(to: output, quality: quality) else {
            if decoded.isDamaged { throw ConversionError.damaged(source) }
            throw CocoaError(.fileWriteUnknown, userInfo: [NSURLErrorKey: destination])
        }
    }

    /// How many bytes converting `decoded` to `type` writes, found by encoding it in memory exactly
    /// as `convert` encodes it to a file. Nil if encoding fails.
    static func encodedSize(of decoded: Decoded, as type: UTType, quality: Double?) -> Int? {
        let data = NSMutableData()
        guard let output = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil),
              decoded.write(to: output, quality: quality)
        else { return nil }
        return data.length
    }

    /// An image decoded for conversion: full size, upright, with the metadata to carry over.
    struct Decoded: @unchecked Sendable {
        let image: CGImage
        let properties: [CFString: Any]

        /// Throws `ConversionError.damaged` when `source` can't be decoded.
        init(_ source: URL) throws {
            guard let input = CGImageSourceCreateWithURL(source as CFURL, nil),
                  CGImageSourceGetStatus(input) == .statusComplete
            else { throw ConversionError.damaged(source) }
            let index = CGImageSourceGetPrimaryImageIndex(input)
            let properties = CGImageSourceCopyPropertiesAtIndex(input, index, nil) as? [CFString: Any] ?? [:]
            guard CGImageSourceGetStatusAtIndex(input, index) == .statusComplete,
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  let image = ImageConversion.uprightImage(input, at: index, longestSide: max(width, height))
            else { throw ConversionError.damaged(source) }
            (self.image, self.properties) = (image, properties)
        }

        /// Some formats (HEIC) decode lazily, so a truncated file only fails when it is encoded.
        var isDamaged: Bool { image.dataProvider?.data == nil }

        func write(to output: CGImageDestination, quality: Double?) -> Bool {
            CGImageDestinationAddImage(output, image, options(for: image, from: properties, quality: quality) as CFDictionary)
            return CGImageDestinationFinalize(output)
        }
    }

    /// How every output is written: with `properties`' metadata, at `quality` (0 to 1, for lossy
    /// formats; nil leaves it to ImageIO), and transparency flattened onto white where the format
    /// has no alpha. Size estimates encode with the same options.
    static func options(for image: CGImage, from properties: [CFString: Any], quality: Double?) -> [CFString: Any] {
        var options = metadata(from: properties, for: image)
        if let quality { options[kCGImageDestinationLossyCompressionQuality] = quality }
        // Formats without alpha (JPEG) composite transparent areas onto this; ImageIO documents
        // black as the default. Formats with alpha ignore it.
        options[kCGImageDestinationBackgroundColor] = CGColor(gray: 1, alpha: 1)
        return options
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
