import Foundation
import UniformTypeIdentifiers

/// Converts any image to PNG.
public struct PNGAction: ConversionAction {
    public init() {}

    public var name: String { "PNG" }
    public var outputType: UTType { .png }

    public func accepts(_ file: SourceFile) -> Bool {
        file.kind == .image && !file.contentType.conforms(to: .png)
    }

    public func perform(_ file: SourceFile, writingTo destination: URL) async throws {
        try ImageConversion.convert(file.url, to: destination, as: outputType)
    }
}
