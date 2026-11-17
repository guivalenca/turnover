import CoreGraphics
import Foundation
import ImageIO

/// What ImageIO sees in an image file, read independently of TurnoverKit so tests can check outputs.
/// Pixel coordinates are in the stored image, top-left origin, with no orientation applied.
public struct ImageFacts {
    /// The format ImageIO detected from the bytes, e.g. "public.png".
    public let typeIdentifier: String
    public let width: Int
    public let height: Int
    /// EXIF orientation, 1 (upright) when the file has none.
    public let orientation: Int
    /// The embedded colour profile's name, e.g. "Display P3".
    public let profileName: String?
    public let exif: [String: Any]
    public let gps: [String: Any]
    public let tiff: [String: Any]
    private let image: CGImage

    public init(_ url: URL) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let type = CGImageSourceGetType(source),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { throw CocoaError(.fileReadCorruptFile, userInfo: [NSURLErrorKey: url]) }
        typeIdentifier = type as String
        width = image.width
        height = image.height
        orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        profileName = properties[kCGImagePropertyProfileName] as? String
        exif = properties[kCGImagePropertyExifDictionary] as? [String: Any] ?? [:]
        gps = properties[kCGImagePropertyGPSDictionary] as? [String: Any] ?? [:]
        tiff = properties[kCGImagePropertyTIFFDictionary] as? [String: Any] ?? [:]
        self.image = image
    }

    /// The pixel at (x, y) as 8-bit sRGB red, green, blue, alpha.
    public func pixel(x: Int, y: Int) -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
        var bytes = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // Shift the image so that the wanted pixel lands on the 1×1 canvas (CG's origin is bottom-left).
        context.draw(image, in: CGRect(x: -x, y: y - height + 1, width: width, height: height))
        return (bytes[0], bytes[1], bytes[2], bytes[3])
    }

    /// True when the pixel at (x, y) is clearly the red marker every fixture has in its top-left corner.
    public func isMarkerRed(x: Int, y: Int) -> Bool {
        let p = pixel(x: x, y: y)
        return p.red > 200 && p.green < 80 && p.blue < 80
    }
}
