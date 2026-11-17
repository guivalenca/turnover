import Foundation
import UniformTypeIdentifiers

/// Converts any image to JPEG.
public struct JPEGAction: ConversionAction {
    public init() {}

    public var name: String { "JPEG" }
    public var outputType: UTType { .jpeg }
    /// "jpg", the extension people expect, rather than UTType's preferred "jpeg".
    public var fileExtension: String { "jpg" }

    public func accepts(_ file: SourceFile) -> Bool {
        file.kind == .image && !file.contentType.conforms(to: .jpeg)
    }

    public func perform(_ file: SourceFile, writingTo destination: URL) async throws {
        try ImageConversion.convert(file.url, to: destination, as: outputType)
    }
}
