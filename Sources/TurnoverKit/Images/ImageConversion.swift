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
        guard write(decoded.image(as: type), with: decoded.properties, to: output, quality: quality) else {
            if decoded.isDamaged { throw ConversionError.damaged(source) }
            throw CocoaError(.fileWriteUnknown, userInfo: [NSURLErrorKey: destination])
        }
    }

    /// How many bytes converting `decoded` to `type` writes, found by encoding it in memory exactly
    /// as `convert` encodes it to a file. Nil if encoding fails.
    static func encodedSize(of decoded: Decoded, as type: UTType, quality: Double?) -> Int? {
        encodedSize(of: decoded.image(as: type), with: decoded.properties, as: type, quality: quality)
    }

    /// How many bytes `image` takes as `type`, with `properties`' metadata, written as every
    /// output is. Nil if encoding fails. Size estimates encode their samples with it too.
    static func encodedSize(of image: CGImage, with properties: [CFString: Any], as type: UTType,
                            quality: Double?) -> Int? {
        let data = NSMutableData()
        guard let output = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil),
              write(image, with: properties, to: output, quality: quality)
        else { return nil }
        return data.length
    }

    /// Adds `image` to `output` with `options(for:from:quality:)`, and finishes it.
    private static func write(_ image: CGImage, with properties: [CFString: Any], to output: CGImageDestination,
                              quality: Double?) -> Bool {
        CGImageDestinationAddImage(output, image, options(for: image, from: properties, quality: quality) as CFDictionary)
        return CGImageDestinationFinalize(output)
    }

    /// An image decoded for conversion: full size, upright, with the metadata to carry over.
    struct Decoded: Sendable {
        let image: CGImage
        private let metadata: Metadata
        /// The source's ImageIO properties, metadata included.
        var properties: [CFString: Any] { metadata.properties }
        /// The hardware decoder gave an opaque picture an alpha channel (see `opaque(_:)`).
        let hasSpareAlpha: Bool

        /// Throws `ConversionError.damaged` when `source` can't be decoded.
        init(_ source: URL) throws {
            guard let header = ImageHeader(source),
                  let image = ImageConversion.uprightImage(header.source, at: header.index,
                                                           longestSide: max(header.width, header.height))
            else { throw ConversionError.damaged(source) }
            (self.image, metadata) = (image, Metadata(properties: header.properties))
            hasSpareAlpha = header.decodesInHardware && !header.hasAlpha
        }

        /// Some formats (HEIC) decode lazily, so a truncated file only fails when it is encoded.
        var isDamaged: Bool { image.dataProvider?.data == nil }

        /// The image to write as `type`. JPEG has no alpha to store, and keeps the hardware
        /// decode's faster encoder.
        func image(as type: UTType) -> CGImage {
            hasSpareAlpha && type != .jpeg ? ImageConversion.opaque(image) : image
        }
    }

    /// ImageIO's properties of a source: property-list values only (strings, numbers, arrays and
    /// dictionaries of them), copied out of the source and never changed afterwards, so reading
    /// them from several threads is safe. Swift can't see that through `Any`, hence unchecked.
    private struct Metadata: @unchecked Sendable {
        let properties: [CFString: Any]
    }

    /// How every output is written: with `properties`' metadata, at `quality` (0 to 1, for lossy
    /// formats; nil leaves it to ImageIO), and transparency flattened onto white where the format
    /// has no alpha. Size estimates encode with the same options.
    private static func options(for image: CGImage, from properties: [CFString: Any], quality: Double?) -> [CFString: Any] {
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

    /// `image` without its alpha channel, for a source that has none: the hardware decoder (HEIC,
    /// HEIF, AVIF) adds one, and a PNG would store it, about 10% bigger for nothing. The pixels
    /// stay where they are, nothing is copied, and only the alpha byte is skipped. Opaque
    /// premultiplied pixels are the same as plain ones, so nothing changes colour.
    private static func opaque(_ image: CGImage) -> CGImage {
        let skipped: CGImageAlphaInfo
        switch image.alphaInfo {
        case .premultipliedFirst, .first: skipped = .noneSkipFirst
        case .premultipliedLast, .last: skipped = .noneSkipLast
        default: return image  // opaque already, or alpha only (a mask)
        }
        let others = image.bitmapInfo.rawValue & ~CGBitmapInfo.alphaInfoMask.rawValue
        guard let space = image.colorSpace, let pixels = image.dataProvider,
              let opaque = CGImage(width: image.width, height: image.height, bitsPerComponent: image.bitsPerComponent,
                                   bitsPerPixel: image.bitsPerPixel, bytesPerRow: image.bytesPerRow, space: space,
                                   bitmapInfo: CGBitmapInfo(rawValue: others | skipped.rawValue), provider: pixels,
                                   decode: nil, shouldInterpolate: image.shouldInterpolate, intent: image.renderingIntent)
        else { return image }
        return opaque
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
