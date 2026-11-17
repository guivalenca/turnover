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

    /// Converts `source` with `action` and returns where the new file landed.
    ///
    /// The output appears next to the source, named like it with the action's extension and a
    /// Finder-style number if that name is taken, carrying the source's creation and modification
    /// dates. It appears complete or not at all; the source and existing files are never touched.
    ///
    /// Throws `ConversionError` when the file can't be read, isn't something `action` accepts, or
    /// can't be decoded. File-system failures while writing (for example a read-only folder)
    /// surface as the underlying Cocoa or POSIX error.
    public func convert(_ source: URL, with action: some ConversionAction) async throws -> ConversionResult {
        let file = try SourceFile(source)
        guard action.accepts(file) else { throw refusal(of: file, by: action) }
        let placement = Placement(nextTo: source, fileExtension: action.fileExtension)
        let output = try await placement.place { temporary in
            try await action.perform(file, writingTo: temporary)
        }
        return ConversionResult(source: source, output: output)
    }

    private func refusal(of file: SourceFile, by action: some ConversionAction) -> ConversionError {
        if file.kind == .unsupported {
            return .unsupported(file.url, typeDescription: file.contentType.localizedDescription ?? file.contentType.identifier)
        }
        if file.contentType.conforms(to: action.outputType) {
            return .alreadyInFormat(file.url, format: action.name)
        }
        return .notApplicable(file.url, format: action.name)
    }
}
