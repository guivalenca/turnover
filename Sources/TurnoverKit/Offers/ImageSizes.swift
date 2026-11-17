import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Roughly how large one image becomes in each output format, found by encoding it in memory
/// with the options the real conversion uses.
struct ImageSizes: Sendable {
    let png: Int
    let jpeg: [JPEGQuality: Int]

    /// Nil when the image can't be decoded.
    init?(of url: URL) {
        guard let input = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetStatus(input) == .statusComplete
        else { return nil }
        let index = CGImageSourceGetPrimaryImageIndex(input)
        let properties = CGImageSourceCopyPropertiesAtIndex(input, index, nil) as? [CFString: Any] ?? [:]
        guard let image = CGImageSourceCreateImageAtIndex(input, index, nil),
              let png = Self.encodedSize(of: image, as: .png, properties: properties, quality: nil)
        else { return nil }
        var jpeg: [JPEGQuality: Int] = [:]
        for quality in JPEGQuality.allCases {
            guard let size = Self.encodedSize(of: image, as: .jpeg, properties: properties, quality: quality.encoderQuality)
            else { return nil }
            jpeg[quality] = size
        }
        (self.png, self.jpeg) = (png, jpeg)
    }

    func bytes(as format: OutputFormat, quality: JPEGQuality) -> Int {
        format == .png ? png : jpeg[quality]!
    }

    private static func encodedSize(of image: CGImage, as type: UTType, properties: [CFString: Any], quality: Double?) -> Int? {
        let data = NSMutableData()
        guard let output = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(output, image, ImageConversion.options(for: image, from: properties, quality: quality) as CFDictionary)
        return CGImageDestinationFinalize(output) ? data.length : nil
    }
}
