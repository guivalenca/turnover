import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// How large one image becomes in each output format, found by encoding it in memory with the
/// options the real conversion uses: the whole image for a small one (exact), or a sample of a
/// large one (approximate). `Refinement` measures large ones exactly later.
///
/// A large image is sampled with pieces at full resolution, never a downscaled copy: shrinking a
/// photo packs more detail into each pixel and overestimates the output two- or threefold, and a
/// flat graphic far more. See `Sample`.
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
        let sampled = Array(spread(unknown).prefix(sampledImages))
        var measured = await quick(sampled)
        measured.merge(known) { quick, _ in quick }
        let unsampled = unknown.filter { !sampled.contains($0) }
        return completing(measured, for: images, pixels: pixelCounts(of: unsampled))
    }

    /// Quick sizes for `images`, measured side by side; the ones that can't be decoded are left out.
    static func quick(_ images: [SourceFile]) async -> [URL: ImageSizes] {
        await withTaskGroup(of: (URL, ImageSizes?).self) { group in
            for image in images { group.addTask { (image.url, ImageSizes(of: image)) } }
            return await group.reduce(into: [URL: ImageSizes]()) { $0[$1.0] = $1.1 }
        }
    }

    /// `measured`, plus an approximate size for each other image of `images` whose pixel count is
    /// in `pixels`, scaled from the measured images.
    ///
    /// `quick` holds the quick estimates of images since measured exactly. Each format's quick
    /// estimates are calibrated by them: multiplied by how far off they turned out on that format.
    static func completing(_ measured: [URL: ImageSizes], for images: [SourceFile], pixels: [URL: Int],
                           quick: [URL: ImageSizes] = [:]) -> [URL: ImageSizes] {
        let selected = Set(images.map(\.url))
        var sizes = measured.filter { selected.contains($0.key) }
        let ratios = calibration(of: quick, by: sizes, for: images)
        for image in images {
            guard var own = sizes[image.url] else { continue }
            for (output, size) in own.sizes where !size.isExact {
                guard let ratio = ratios[Calibrated(type: image.contentType, output: output)] else { continue }
                own.sizes[output] = Size(bytes: Int(Double(size.bytes) * ratio), isExact: false)
            }
            sizes[image.url] = own
        }
        let references = images.compactMap { image in sizes[image.url].map { (image, $0) } }
        for image in images where sizes[image.url] == nil {
            guard let count = pixels[image.url], let scaled = ImageSizes(scaling: references, to: count, like: image)
            else { continue }
            sizes[image.url] = scaled
        }
        return sizes
    }

    private struct Calibrated: Hashable {
        let type: UTType
        let output: ImageOutput
    }

    /// For each source format and output, the exact sizes of the images measured since their
    /// quick estimate, divided by those quick estimates.
    private static func calibration(of quick: [URL: ImageSizes], by measured: [URL: ImageSizes],
                                    for images: [SourceFile]) -> [Calibrated: Double] {
        var sums: [Calibrated: (exact: Int, quick: Int)] = [:]
        for image in images {
            guard let guesses = quick[image.url], let sizes = measured[image.url] else { continue }
            for (output, guess) in guesses.sizes where !guess.isExact && guess.bytes > 0 {
                guard let size = sizes.sizes[output], size.isExact else { continue }
                let key = Calibrated(type: image.contentType, output: output)
                sums[key, default: (0, 0)].exact += size.bytes
                sums[key, default: (0, 0)].quick += guess.bytes
            }
        }
        return sums.mapValues { Double($0.exact) / Double($0.quick) }
    }

    /// Every image, taking one of each format in turn, in selection order: the first few are a
    /// fair sample of a mixed selection.
    static func spread(_ images: [SourceFile]) -> [SourceFile] {
        var byFormat: [[SourceFile]] = []
        for image in images {
            if let index = byFormat.firstIndex(where: { $0[0].contentType == image.contentType }) {
                byFormat[index].append(image)
            } else {
                byFormat.append([image])
            }
        }
        var order: [SourceFile] = []
        for round in 0..<(byFormat.map(\.count).max() ?? 0) {
            for format in byFormat where round < format.count { order.append(format[round]) }
        }
        return order
    }

    /// The pixel count of each image in `images` whose header can be read.
    static func pixelCounts(of images: [SourceFile]) -> [URL: Int] {
        images.reduce(into: [:]) { counts, image in counts[image.url] = pixelCount(of: image.url) }
    }

    /// From the header alone. Nil when the image can't be decoded.
    static func pixelCount(of url: URL) -> Int? {
        guard let input = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetStatus(input) == .statusComplete,
              let properties = CGImageSourceCopyPropertiesAtIndex(input, CGImageSourceGetPrimaryImageIndex(input), nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return width * height
    }

    /// An image like `image`, of `pixels` pixels, with as many bytes per pixel in each output as
    /// the `references` of its own format together, or all of them when none has its format;
    /// among those, only the ones measured exactly, if any are. Always approximate.
    private init?(scaling references: [(SourceFile, ImageSizes)], to pixels: Int, like image: SourceFile) {
        var sizes: [ImageOutput: Size] = [:]
        for output in ImageOutput.allCases {
            let having = references.filter { $0.1.sizes[output] != nil && $0.1.pixels > 0 }
            let sameFormat = having.filter { $0.0.contentType == image.contentType }
            let pool = sameFormat.isEmpty ? having : sameFormat
            let exact = pool.filter { $0.1.sizes[output]!.isExact }
            let basis = (exact.isEmpty ? pool : exact).map(\.1)
            let basisPixels = basis.reduce(0) { $0 + $1.pixels }
            guard basisPixels > 0 else { continue }
            let bytes = basis.reduce(0) { $0 + $1.sizes[output]!.bytes }
            sizes[output] = Size(bytes: Int(Double(bytes) * Double(pixels) / Double(basisPixels)), isExact: false)
        }
        guard !sizes.isEmpty else { return nil }
        (self.pixels, self.sizes) = (pixels, sizes)
    }

    /// Images up to this many pixels are measured exactly, as cheaply as a sample of a big one.
    static let wholeImageLimit = 150_000

    /// Measures one image: exactly when it is small, from a sample otherwise. Nil when it can't
    /// be decoded.
    init?(of file: SourceFile) {
        guard let input = CGImageSourceCreateWithURL(file.url as CFURL, nil),
              CGImageSourceGetStatus(input) == .statusComplete
        else { return nil }
        let index = CGImageSourceGetPrimaryImageIndex(input)
        let properties = CGImageSourceCopyPropertiesAtIndex(input, index, nil) as? [CFString: Any] ?? [:]
        guard let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        var sizes: [ImageOutput: Size] = [:]
        if width * height <= Self.wholeImageLimit {
            guard let decoded = try? ImageConversion.Decoded(file.url) else { return nil }
            for output in ImageOutput.allCases {
                guard let bytes = ImageConversion.encodedSize(of: decoded, as: output.type, quality: output.encoderQuality)
                else { return nil }
                sizes[output] = Size(bytes: bytes, isExact: true)
            }
        } else {
            // Decoded lazily, so a piece of a tiled HEIC decodes only its tile.
            guard let image = CGImageSourceCreateImageAtIndex(input, index, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let sample = Sample(image, properties: properties, from: file)
            else { return nil }
            for output in ImageOutput.allCases {
                guard let bytes = sample.bytes(as: output) else { return nil }
                sizes[output] = Size(bytes: bytes, isExact: false)
            }
        }
        (self.pixels, self.sizes) = (width * height, sizes)
    }

    init(pixels: Int, sizes: [ImageOutput: Size]) {
        (self.pixels, self.sizes) = (pixels, sizes)
    }

    /// Wide, short pieces of an image at full resolution, stacked into one picture that is
    /// encoded once per output; the result is scaled up by pixel count.
    ///
    /// Rows are what PNG compresses and JPEG encodes in 16-row strips, so pieces 16 or 32 rows
    /// high and 512 wide behave as they do in the whole image, unlike small squares. They are
    /// spread over a grid: 18 of them, or 9 taller ones in a tiled image (a HEIC from a camera
    /// has 512-pixel tiles), each inside a single tile, since every piece decodes the tiles it
    /// touches.
    ///
    /// On 74 real photos (stock JPEGs, wallpapers and HEICs made from them) and 6 screenshots and
    /// graphics, this came within 0.81 to 1.46 of the real output, against 0.34 to 2.09 for five
    /// 128-pixel squares, in the same time (`QuickEstimateAccuracy` measures it).
    private struct Sample {
        let mosaic: CGImage
        let properties: [CFString: Any]
        let imagePixels: Int
        /// See `hardwareJPEGRatio`.
        let decodesInHardware: Bool

        init?(_ image: CGImage, properties: [CFString: Any], from file: SourceFile) {
            let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
            let tile = (tiff?[kCGImagePropertyTIFFTileWidth] as? Int ?? 0, tiff?[kCGImagePropertyTIFFTileLength] as? Int ?? 0)
            let tiled = tile.0 > 0 && tile.1 > 0
            let (width, height) = (image.width, image.height)
            let pieceWidth = min(512, width, tiled ? tile.0 : width)
            let pieceHeight = min(tiled ? 32 : 16, height, tiled ? tile.1 : height)
            let (columns, rows) = tiled ? (3, 3) : (3, 6)
            decodesInHardware = Self.decodesInHardware(file)
            guard let context = Self.context(like: image, width: pieceWidth, height: pieceHeight * columns * rows,
                                             alpha: decodesInHardware)
            else { return nil }
            var stacked = 0
            for row in 0..<rows {
                for column in 0..<columns {
                    var x = (2 * column + 1) * width / (2 * columns) - pieceWidth / 2
                    var y = (2 * row + 1) * height / (2 * rows) - pieceHeight / 2
                    if tiled {
                        let tileX = (x + pieceWidth / 2) / tile.0 * tile.0, tileY = (y + pieceHeight / 2) / tile.1 * tile.1
                        x = min(max(x, tileX), tileX + tile.0 - pieceWidth)
                        y = min(max(y, tileY), tileY + tile.1 - pieceHeight)
                    }
                    x = min(max(0, x), width - pieceWidth)
                    y = min(max(0, y), height - pieceHeight)
                    guard let piece = image.cropping(to: CGRect(x: x, y: y, width: pieceWidth, height: pieceHeight))
                    else { return nil }
                    context.draw(piece, in: CGRect(x: 0, y: stacked * pieceHeight, width: pieceWidth, height: pieceHeight))
                    stacked += 1
                }
            }
            guard let mosaic = context.makeImage() else { return nil }
            (self.mosaic, self.properties, imagePixels) = (mosaic, properties, width * height)
        }

        func bytes(as output: ImageOutput) -> Int? {
            let (type, quality) = (output.type, output.encoderQuality)
            // The fixed cost of headers, metadata and the colour profile, measured on a crop too
            // small for its pixels to matter: paid once by the output, and once by the mosaic.
            guard let corner = mosaic.cropping(to: CGRect(x: 0, y: 0, width: 16, height: 16)),
                  let fixed = Self.encodedSize(of: corner, as: type, metadata: properties, quality: quality),
                  let bare = Self.encodedSize(of: corner, as: type, metadata: [:], quality: quality),
                  let whole = Self.encodedSize(of: mosaic, as: type, metadata: [:], quality: quality)
            else { return nil }
            let samplePixels = mosaic.width * mosaic.height - corner.width * corner.height
            var bytes = Double(max(0, whole - bare)) * Double(imagePixels) / Double(samplePixels)
            if decodesInHardware, case .jpeg(let preset) = output { bytes *= Self.hardwareJPEGRatio[preset]! }
            return fixed + Int(bytes)
        }

        /// HEIC, HEIF and AVIF decode through the hardware path. The conversion's decoded image
        /// then has an alpha channel (so its PNG has one too), and its JPEGs go through a faster
        /// encoder that writes smaller files than the same pixels copied into a sample do: on 54
        /// HEICs, by these factors (geometric means; individual photos ranged ±15%).
        static let hardwareJPEGRatio: [JPEGQuality: Double] = [.best: 0.82, .high: 0.91, .small: 0.88]

        private static func decodesInHardware(_ file: SourceFile) -> Bool {
            [UTType.heic, .heif, UTType("public.avif")].contains { $0.map(file.contentType.conforms) ?? false }
        }

        /// A bitmap for the pieces with the decoded image's channels and depth, plus alpha when
        /// the conversion's decode adds one, so a PNG of it is as big as the conversion's would be.
        private static func context(like image: CGImage, width: Int, height: Int, alpha: Bool) -> CGContext? {
            let opaque = !alpha && [.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo)
            let depth = image.bitsPerComponent > 8 ? 16 : 8
            let space = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
            let layout: (CGColorSpace, CGImageAlphaInfo) =
                if space.model == .monochrome && opaque { (space, .none) }
                else if space.model == .rgb { (space, opaque ? .noneSkipLast : .premultipliedLast) }
                else { (CGColorSpace(name: CGColorSpace.sRGB)!, opaque ? .noneSkipLast : .premultipliedLast) }
            return CGContext(data: nil, width: width, height: height, bitsPerComponent: depth,
                             bytesPerRow: 0, space: layout.0, bitmapInfo: layout.1.rawValue)
                ?? CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                             bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        }

        private static func encodedSize(of image: CGImage, as type: UTType, metadata: [CFString: Any], quality: Double?) -> Int? {
            let data = NSMutableData()
            guard let output = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { return nil }
            CGImageDestinationAddImage(output, image, ImageConversion.options(for: image, from: metadata, quality: quality) as CFDictionary)
            return CGImageDestinationFinalize(output) ? data.length : nil
        }
    }
}
