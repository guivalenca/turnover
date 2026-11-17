import Foundation

/// The result of converting one file.
public struct ConversionResult: Sendable, Hashable {
    /// The file that was converted. It is never modified.
    public let source: URL
    /// The new file.
    public let output: URL
}

/// Converts single files with an action and places the output next to the original.
public struct Converter: Sendable {
    public init() {}

    public func convert(_ source: URL, with action: some ConversionAction) async throws -> ConversionResult {
        let file = SourceFile(source)
        let placement = Placement(nextTo: source, fileExtension: action.outputType.preferredFilenameExtension!)
        let output = try await placement.place { temporary in
            try await action.perform(file, writingTo: temporary)
        }
        return ConversionResult(source: source, output: output)
    }
}
