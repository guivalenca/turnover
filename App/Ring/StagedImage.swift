import AppKit
import ImageIO

/// An image dragged out of a web page, written to a file of its own: a private temporary folder
/// holding just "mountain-lake.webp". From there it is estimated and converted like any file,
/// with the folder the drop chose as its destination.
struct StagedImage: Sendable {
    let file: URL

    /// Writes `data` as `name` in a new temporary folder, off the main actor.
    static func write(_ data: Data, named name: String) async throws -> StagedImage {
        try await Task.detached(priority: .userInitiated) {
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("Turnover-dragged-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appendingPathComponent(name)
            try data.write(to: file)
            return StagedImage(file: file)
        }.value
    }

    /// A small picture of it, `side` points at most, for the drag image over the ring. Decoded
    /// off the main actor: a large PNG takes a moment. Nil when ImageIO can't draw it.
    func thumbnail(side: CGFloat) async -> NSImage? {
        let file = file
        let pixels = side * (await MainActor.run { NSScreen.main?.backingScaleFactor ?? 2 })
        let image = await Task.detached(priority: .userInitiated) { () -> CGImage? in
            guard let source = CGImageSourceCreateWithURL(file as CFURL, nil) else { return nil }
            return CGImageSourceCreateThumbnailAtIndex(source, CGImageSourceGetPrimaryImageIndex(source), [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: pixels,
            ] as CFDictionary)
        }.value
        return image.map { NSImage(cgImage: $0, size: NSSize(width: CGFloat($0.width) * side / pixels,
                                                             height: CGFloat($0.height) * side / pixels)) }
    }

    /// Deletes the temporary folder, once nothing reads the file any more.
    func remove() {
        try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
    }
}
