import Foundation
import UniformTypeIdentifiers

/// One kind of conversion, for example "make a PNG". Options (such as a JPEG quality) are the
/// action's stored properties, so a configured action value is everything needed to run it.
///
/// An action only produces bytes. `Converter` does the rest: it inspects the source, asks the
/// action whether it applies, hands it a temporary destination, then names, places and dates
/// the output. New outputs (JPEG, MP4, later PDF or trimming) plug in as new conformances.
public protocol ConversionAction: Sendable {
    /// The short name users see, e.g. "PNG".
    var name: String { get }

    /// The format the action writes.
    var outputType: UTType { get }

    /// The output's filename extension, without the dot. Defaults to `outputType`'s preferred one.
    var fileExtension: String { get }

    /// Whether the action can convert `file`. Must be false for a file already in `outputType`.
    func accepts(_ file: SourceFile) -> Bool

    /// Writes `file`, converted, to `destination`: a path in a private temporary folder whose
    /// name already ends in the output extension. Throw `ConversionError` to fail with a reason.
    func perform(_ file: SourceFile, writingTo destination: URL) async throws
}

extension ConversionAction {
    public var fileExtension: String { outputType.preferredFilenameExtension ?? "out" }
}
