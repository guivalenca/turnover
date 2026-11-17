import CoreGraphics
import Foundation
import ImageIO

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
