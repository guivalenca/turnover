import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// An image file opened with ImageIO, with its primary picture's properties read from the
/// header: what every decode and size estimate starts from. Nothing is decoded yet.
struct ImageHeader {
    let source: CGImageSource
    /// The primary picture's index (a HEIC may hold several pictures).
    let index: Int
    let properties: [CFString: Any]
    let width: Int
    let height: Int

    var pixels: Int { width * height }

    /// Whether the picture stores transparency.
    var hasAlpha: Bool { properties[kCGImagePropertyHasAlpha] as? Bool == true }

    /// HEIC, HEIF and AVIF decode through the hardware path. The decoded picture then has an
    /// alpha channel even when the file has none, and its JPEGs go through a faster encoder.
    var decodesInHardware: Bool {
        guard let identifier = CGImageSourceGetType(source), let type = UTType(identifier as String) else { return false }
        return [UTType.heic, .heif, UTType("public.avif")].contains { $0.map(type.conforms) ?? false }
    }

    /// Nil when the file can't be decoded: ImageIO doesn't read it, or it is incomplete, which
    /// includes a HEIC or AVIF cut short (see `HEIFItems`).
    init?(_ url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetStatus(source) == .statusComplete
        else { return nil }
        let index = CGImageSourceGetPrimaryImageIndex(source)
        guard CGImageSourceGetStatusAtIndex(source, index) == .statusComplete,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              HEIFItems.areComplete(in: url)
        else { return nil }
        (self.source, self.index, self.properties, self.width, self.height) = (source, index, properties, width, height)
    }
}
