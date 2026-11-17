import Foundation
import UniformTypeIdentifiers

/// Converts any image to PNG.
public struct PNGAction: ConversionAction {
    public init() {}

    public var outputType: UTType { .png }

    public func accepts(_ file: SourceFile) -> Bool { true }

    public func perform(_ file: SourceFile, writingTo destination: URL) async throws {
        try ImageConversion.convert(file.url, to: destination, as: outputType)
    }
}
