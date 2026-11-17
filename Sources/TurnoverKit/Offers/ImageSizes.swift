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
///
/// A selection is sampled too: at most `sampledImages` of its images are measured, spread across
/// their formats, and each of the others is scaled from the measured images of its own format by
/// pixel count. Decoding a HEIC takes the hardware decoder, which serialises, so measuring ten
/// 12-megapixel HEICs took about 90 ms and four take about 40.
struct ImageSizes: Sendable {
    let pixels: Int
    /// The size of each output measured or scaled so far.
    var sizes: [ImageOutput: Size]

    /// One output's size, and whether it was measured exactly or is a guess.
    struct Size: Sendable, Hashable {
        var bytes: Int
        var isExact: Bool
    }

    static let sampledImages = 4

    /// The sizes of every image in `images` that can be decoded. Images in `known` (exact sizes
    /// remembered from earlier) are taken as they are, and also serve to scale the others.
    static func of(_ images: [SourceFile], known: [URL: ImageSizes] = [:]) async -> [URL: ImageSizes] {
        let unknown = images.filter { known[$0.url] == nil }
        let sampled = samples(of: unknown)
        let measured = await withTaskGroup(of: (SourceFile, ImageSizes?).self) { group in
            for image in sampled { group.addTask { (image, ImageSizes(of: image.url)) } }
            return await group.reduce(into: [SourceFile: ImageSizes]()) { $0[$1.0] = $1.1 }
        }
        var sizes = known.filter { url, _ in images.contains { $0.url == url } }
        for (image, measurement) in measured { sizes[image.url] = measurement }
        let references = images.compactMap { image in sizes[image.url].map { (image, $0) } }
        for image in unknown where sizes[image.url] == nil && !sampled.contains(image) {
            guard let pixels = pixelCount(of: image.url),
                  let scaled = ImageSizes(scaling: references, to: pixels, like: image)
            else { continue }
            sizes[image.url] = scaled
        }
        return sizes
    }

    /// Up to `sampledImages` images, taking one of each format in turn, in selection order.
    private static func samples(of images: [SourceFile]) -> Set<SourceFile> {
        var byFormat: [[SourceFile]] = []
        for image in images {
            if let index = byFormat.firstIndex(where: { $0[0].contentType == image.contentType }) {
                byFormat[index].append(image)
            } else {
                byFormat.append([image])
            }
        }
        var picked: Set<SourceFile> = []
        for round in 0..<sampledImages {
            for format in byFormat where round < format.count && picked.count < sampledImages {
                picked.insert(format[round])
            }
        }
        return picked
    }

    /// From the header alone. Nil when the image can't be decoded.
    private static func pixelCount(of url: URL) -> Int? {
        guard let input = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetStatus(input) == .statusComplete,
              let properties = CGImageSourceCopyPropertiesAtIndex(input, CGImageSourceGetPrimaryImageIndex(input), nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return width * height
    }

    /// An image like `image`, of `pixels` pixels, with as many bytes per pixel in each output as
    /// the `references` of its own format together, or all of them when none has its format.
    /// Always approximate.
    private init?(scaling references: [(SourceFile, ImageSizes)], to pixels: Int, like image: SourceFile) {
        var sizes: [ImageOutput: Size] = [:]
        for output in ImageOutput.allCases {
            let having = references.filter { $0.1.sizes[output] != nil && $0.1.pixels > 0 }
            let sameFormat = having.filter { $0.0.contentType == image.contentType }
            let basis = (sameFormat.isEmpty ? having : sameFormat).map(\.1)
            let basisPixels = basis.reduce(0) { $0 + $1.pixels }
            guard basisPixels > 0 else { continue }
            let bytes = basis.reduce(0) { $0 + $1.sizes[output]!.bytes }
            sizes[output] = Size(bytes: Int(Double(bytes) * Double(pixels) / Double(basisPixels)), isExact: false)
        }
        guard !sizes.isEmpty else { return nil }
        (self.pixels, self.sizes) = (pixels, sizes)
    }

    /// Images up to this many pixels are encoded whole (the fixtures are).
    static let wholeImageLimit = tileCount * tileSide * tileSide
    static let tileSide = 128
    /// The centre, and the centre of each quarter.
    static let tileCount = 5

    /// Measures one image. Nil when it can't be decoded.
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
        var sizes: [ImageOutput: Size] = [:]
        for output in ImageOutput.allCases {
            guard let bytes = sample.bytes(as: output.type, quality: output.encoderQuality) else { return nil }
            sizes[output] = Size(bytes: bytes, isExact: false)
        }
        (self.pixels, self.sizes) = (image.width * image.height, sizes)
    }

    init(pixels: Int, sizes: [ImageOutput: Size]) {
        (self.pixels, self.sizes) = (pixels, sizes)
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
                    .flatMap(Self.decoded)
            }
        }

        func bytes(as type: UTType, quality: Double?) -> Int? {
            guard !tiles.isEmpty else { return encodedSize(of: image, as: type, metadata: properties, quality: quality) }
            // The fixed cost, measured on a crop too small for its pixels to matter: with the
            // metadata it is paid once; without it, by every tile.
            guard let corner = tiles[0].cropping(to: CGRect(x: 0, y: 0, width: 8, height: 8)),
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

        /// `crop`'s pixels, decoded once into a bitmap with the same channels and depth, so that
        /// encoding it four times doesn't decode it four times, and a PNG of it is as big as a
        /// PNG of the same pixels in the source would be.
        private static func decoded(_ crop: CGImage) -> CGImage? {
            let opaque = [.none, .noneSkipFirst, .noneSkipLast].contains(crop.alphaInfo)
            let depth = crop.bitsPerComponent > 8 ? 16 : 8
            let space = crop.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
            let layout: (CGColorSpace, CGImageAlphaInfo) =
                if space.model == .monochrome && opaque { (space, .none) }
                else if space.model == .rgb { (space, opaque ? .noneSkipLast : .premultipliedLast) }
                else { (CGColorSpace(name: CGColorSpace.sRGB)!, opaque ? .noneSkipLast : .premultipliedLast) }
            let context = CGContext(data: nil, width: crop.width, height: crop.height, bitsPerComponent: depth,
                                    bytesPerRow: 0, space: layout.0, bitmapInfo: layout.1.rawValue)
                ?? CGContext(data: nil, width: crop.width, height: crop.height, bitsPerComponent: 8,
                             bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
            return context?.makeImage()
        }

        private func encodedSize(of image: CGImage, as type: UTType, metadata: [CFString: Any], quality: Double?) -> Int? {
            let data = NSMutableData()
            guard let output = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { return nil }
            CGImageDestinationAddImage(output, image, ImageConversion.options(for: image, from: metadata, quality: quality) as CFDictionary)
            return CGImageDestinationFinalize(output) ? data.length : nil
        }
    }
}

