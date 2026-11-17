import Foundation
import UniformTypeIdentifiers

/// Converts any image to PNG.
public struct PNGAction: ConversionAction {
    public init() {}

    public var format: OutputFormat { .png }
    public var outputType: UTType { .png }

    public func accepts(_ file: SourceFile) -> Bool {
        file.kind == .image && !file.contentType.conforms(to: .png)
    }

    public func perform(_ file: SourceFile, writingTo destination: URL) async throws {
        // Decoding and encoding block for a while (seconds for a big photo): keep them off the
        // concurrency threads, which the app's other work needs meanwhile.
        let (source, type) = (file.url, outputType)
        try await blocking(.userInitiated, throwing: { try ImageConversion.convert(source, to: destination, as: type) })
    }
}
