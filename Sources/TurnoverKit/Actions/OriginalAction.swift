import Foundation
import UniformTypeIdentifiers

/// Saves an image as it is: a copy, byte for byte, under its own extension. For an image that
/// has no file of its own yet (one dragged out of a web page, staged in a temporary folder),
/// alongside PNG and JPEG. `Offers` only offers it when asked to.
public struct OriginalAction: ConversionAction {
    public init() {}

    public var format: OutputFormat { .original }
    /// Any image: the output's type is the source's.
    public var outputType: UTType { .image }

    public func accepts(_ file: SourceFile) -> Bool {
        file.kind == .image
    }

    /// The source's own extension, or its type's when it has none.
    public func fileExtension(for file: SourceFile) -> String {
        let own = file.url.pathExtension
        return own.isEmpty ? file.contentType.preferredFilenameExtension ?? "img" : own
    }

    public func perform(_ file: SourceFile, writingTo destination: URL) async throws {
        let source = file.url
        try await blocking(.userInitiated, throwing: { try FileManager.default.copyItem(at: source, to: destination) })
    }
}
