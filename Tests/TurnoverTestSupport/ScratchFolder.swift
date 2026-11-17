import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A fresh, empty temporary folder for one test, deleted when the value goes away.
/// Copy fixtures in, convert them there, and look at what appeared.
public final class ScratchFolder: @unchecked Sendable {
    public let url: URL

    public init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TurnoverTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        try? FileManager.default.removeItem(at: url)
    }

    /// Makes the folder read-only, like a disk image or a locked drive: nothing can be added.
    public func makeReadOnly() throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: url.path)
    }

    /// Copies a fixture in, under its own name or `name`, and returns the copy's URL.
    @discardableResult
    public func add(_ fixture: Fixture, as name: String? = nil) throws -> URL {
        let copy = url.appendingPathComponent(name ?? fixture.rawValue)
        try FileManager.default.copyItem(at: fixture.url, to: copy)
        return copy
    }

    /// Writes arbitrary bytes into a new file and returns its URL.
    @discardableResult
    public func add(_ data: Data, as name: String) throws -> URL {
        let file = url.appendingPathComponent(name)
        try data.write(to: file)
        return file
    }

    /// The names in the folder, hidden files included, sorted.
    public func fileNames() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: url.path).sorted()
    }
}

extension ScratchFolder {
    /// Writes a large photo, `width` × `height`, made by repeating a picture fixture at its own
    /// resolution, so it has a real photo's detail per pixel. Fixtures stay tiny; tests that need
    /// a camera-sized image make one. JPEG at 90%, or `type`.
    ///
    /// Faint noise, like a camera sensor's, is laid over it with a period that doesn't line up
    /// with the fixture's. Without it the repeats are exact, and PNG's compressor finds them a
    /// tile apart, which no real photo allows.
    @discardableResult
    public func addMosaic(of fixture: Fixture, width: Int, height: Int, as name: String,
                          type: UTType = .jpeg) throws -> URL {
        guard let source = CGImageSourceCreateWithURL(fixture.url as CFURL, nil),
              let tile = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 100_000,
              ] as CFDictionary),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { throw CocoaError(.fileReadCorruptFile) }
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        for y in stride(from: 0, to: height, by: tile.height) {
            for x in stride(from: 0, to: width, by: tile.width) {
                context.draw(tile, in: CGRect(x: x, y: y, width: tile.width, height: tile.height))
            }
        }
        let noise = sensorNoise()
        context.setAlpha(0.12)
        for y in stride(from: 0, to: height, by: noise.height) {
            for x in stride(from: 0, to: width, by: noise.width) {
                context.draw(noise, in: CGRect(x: x, y: y, width: noise.width, height: noise.height))
            }
        }
        let file = url.appendingPathComponent(name)
        guard let image = context.makeImage(),
              let output = CGImageDestinationCreateWithURL(file as CFURL, type.identifier as CFString, 1, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(output, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(output) else { throw CocoaError(.fileWriteUnknown) }
        return file
    }
}

/// A 509 × 509 grey noise image, the same every time.
private func sensorNoise() -> CGImage {
    let side = 509
    var state: UInt32 = 2_463_534_242
    var pixels = [UInt8](repeating: 0, count: side * side)
    for index in pixels.indices {
        state ^= state << 13; state ^= state >> 17; state ^= state << 5
        pixels[index] = UInt8(truncatingIfNeeded: state)
    }
    let context = CGContext(data: &pixels, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side,
                            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    return context.makeImage()!
}
