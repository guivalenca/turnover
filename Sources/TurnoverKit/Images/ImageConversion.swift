import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Decodes an image with ImageIO and re-encodes it in another format.
enum ImageConversion {
    static func convert(_ source: URL, to destination: URL, as type: UTType) throws {
        guard let input = CGImageSourceCreateWithURL(source as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(input, 0, nil),
              let output = CGImageDestinationCreateWithURL(destination as CFURL, type.identifier as CFString, 1, nil)
        else { throw CocoaError(.fileReadCorruptFile) }
        CGImageDestinationAddImage(output, image, nil)
        guard CGImageDestinationFinalize(output) else { throw CocoaError(.fileWriteUnknown) }
    }
}
