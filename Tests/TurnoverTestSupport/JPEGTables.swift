import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The quantisation tables of a JPEG, which record the quality it was encoded at.
///
/// A file can't say "I am 85%", and ImageIO doesn't use the standard IJG tables, so there is no
/// formula to read the quality back. But ImageIO derives the tables from the quality setting alone
/// (not from the picture), and nearly every whole percentage gives different tables. So a file
/// was written at quality q exactly when its tables equal `JPEGTables(quality: q)`.
public struct JPEGTables: Equatable, Sendable {
    /// Each DQT table's 64 values, in file order (luminance first).
    public let tables: [[Int]]

    /// The tables in the JPEG file at `url`, read from its DQT segments.
    public init(_ url: URL) throws {
        let bytes = [UInt8](try Data(contentsOf: url))
        var tables: [[Int]] = []
        var i = 2  // after SOI
        while i + 4 <= bytes.count, bytes[i] == 0xFF, bytes[i + 1] != 0xDA {  // stop at the scan
            let length = Int(bytes[i + 2]) << 8 | Int(bytes[i + 3])
            if bytes[i + 1] == 0xDB {
                var j = i + 4
                while j < i + 2 + length {
                    let sixteenBit = bytes[j] >> 4 == 1
                    j += 1
                    tables.append((0..<64).map { _ in
                        defer { j += sixteenBit ? 2 : 1 }
                        return sixteenBit ? Int(bytes[j]) << 8 | Int(bytes[j + 1]) : Int(bytes[j])
                    })
                }
            }
            i += 2 + length
        }
        guard !tables.isEmpty else { throw CocoaError(.fileReadCorruptFile, userInfo: [NSURLErrorKey: url]) }
        self.tables = tables
    }

    /// The tables ImageIO writes for an RGB image at `quality`, from 0 to 1.
    public init(quality: Double) {
        let pixel = CGContext(
            data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("JPEGTables-\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: file) }
        let destination = CGImageDestinationCreateWithURL(file as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, pixel.makeImage()!,
                                   [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        precondition(CGImageDestinationFinalize(destination))
        self = try! JPEGTables(file)
    }
}
