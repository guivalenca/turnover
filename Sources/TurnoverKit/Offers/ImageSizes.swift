import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Roughly how large one image becomes in each output format, found by encoding it, or a sample
/// of it, in memory with the options the real conversion uses.
///
/// A large image is sampled with a few tiles at full resolution, never a downscaled copy:
/// shrinking a photo packs more detail into each pixel and overestimates the output two- or
/// threefold, and a flat graphic far more. The tiles' sizes are scaled up by pixel count, and the
/// fixed cost of headers, metadata and the colour profile is added once.
struct ImageSizes: Sendable {
    let png: Int
    let jpeg: [JPEGQuality: Int]

    /// Images up to this many pixels are encoded whole (the fixtures are).
    static let wholeImageLimit = tileCount * tileSide * tileSide
    static let tileSide = 128
    /// The centre, and the centre of each quarter.
    static let tileCount = 5

    /// Nil when the image can't be decoded.
    init?(of url: URL) {
        guard let input = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetStatus(input) == .statusComplete
        else { return nil }
        let index = CGImageSourceGetPrimaryImageIndex(input)
        let properties = CGImageSourceCopyPropertiesAtIndex(input, index, nil) as? [CFString: Any] ?? [:]
        // Decoded lazily, so cropping a tile out of a JPEG or a tiled HEIC decodes only part of it.
        guard let image = CGImageSourceCreateImageAtIndex(input, index, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let sample = Sample(image, properties: properties)
        guard let png = sample.bytes(as: .png, quality: nil) else { return nil }
        var jpeg: [JPEGQuality: Int] = [:]
        for quality in JPEGQuality.allCases {
            guard let size = sample.bytes(as: .jpeg, quality: quality.encoderQuality) else { return nil }
            jpeg[quality] = size
        }
        (self.png, self.jpeg) = (png, jpeg)
    }

    func bytes(as format: OutputFormat, quality: JPEGQuality) -> Int {
        format == .png ? png : jpeg[quality]!
    }

    /// The part of an image that gets encoded, and how to scale the result to the whole.
    private struct Sample {
        let image: CGImage
        let properties: [CFString: Any]
        /// Empty when the image is small enough to encode whole.
        let tiles: [CGImage]

        init(_ image: CGImage, properties: [CFString: Any]) {
            (self.image, self.properties) = (image, properties)
            let (width, height) = (image.width, image.height)
            guard width * height > ImageSizes.wholeImageLimit else { tiles = []; return }
            let side = min(ImageSizes.tileSide, width / 2, height / 2)
            let centres = [(0.5, 0.5), (0.25, 0.25), (0.75, 0.25), (0.25, 0.75), (0.75, 0.75)]
            tiles = centres.compactMap { x, y in
                image.cropping(to: CGRect(x: Int(Double(width) * x) - side / 2, y: Int(Double(height) * y) - side / 2,
                                          width: side, height: side))
            }
        }

        func bytes(as type: UTType, quality: Double?) -> Int? {
            guard !tiles.isEmpty else { return encodedSize(of: image, as: type, metadata: properties, quality: quality) }
            // The fixed cost, measured on a crop too small for its pixels to matter: with the
            // metadata it is paid once; without it, by every tile.
            guard let corner = image.cropping(to: CGRect(x: 0, y: 0, width: 8, height: 8)),
                  let fixed = encodedSize(of: corner, as: type, metadata: properties, quality: quality),
                  let perTile = encodedSize(of: corner, as: type, metadata: [:], quality: quality)
            else { return nil }
            var pixelBytes = 0, pixels = 0
            for tile in tiles {
                guard let size = encodedSize(of: tile, as: type, metadata: [:], quality: quality) else { return nil }
                pixelBytes += max(0, size - perTile)
                pixels += tile.width * tile.height
            }
            return fixed + Int(Double(pixelBytes) * Double(image.width * image.height) / Double(pixels))
        }

        private func encodedSize(of image: CGImage, as type: UTType, metadata: [CFString: Any], quality: Double?) -> Int? {
            let data = NSMutableData()
            guard let output = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { return nil }
            CGImageDestinationAddImage(output, image, ImageConversion.options(for: image, from: metadata, quality: quality) as CFDictionary)
            return CGImageDestinationFinalize(output) ? data.length : nil
        }
    }
}
