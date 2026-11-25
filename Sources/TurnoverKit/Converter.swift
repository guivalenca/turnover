import Foundation

/// The result of converting one file.
public struct ConversionResult: Sendable, Hashable {
    /// The file that was converted. It is never modified.
    public let source: URL
    /// The new file.
    public let output: URL
    /// True when the folder it was meant for (the original's, or the one asked for) couldn't be
    /// written to, so the new file went to Downloads.
    public let savedToDownloads: Bool
    /// What the original was: an image or a video.
    public let kind: SourceFile.Kind
    /// The format it was converted to.
    public let format: OutputFormat
}

/// Converts single files with an action and places the output next to the original.
public struct Converter: Sendable {
    /// Where outputs go when the original's folder can't be written to.
    public let downloads: URL
    /// The conversions this converter and its copies are running.
    let activity = ConversionActivity()

    /// A converter that falls back to `downloads`, the user's Downloads folder unless a test
    /// gives another.
    public init(downloads: URL = .downloadsDirectory) {
        self.downloads = downloads
    }

    /// Converts `source` with `action` and returns where the new file landed.
    ///
    /// The output appears next to the source, named like it (or as the action says) with the action's extension and a
    /// Finder-style number if that name is taken, carrying the source's creation and modification
    /// dates. It appears complete or not at all; the source and existing files are never touched.
    /// When the source's folder can't be written to, the output goes to `downloads` instead, under
    /// the same naming rules, and the result's `savedToDownloads` is true.
    ///
    /// `progress` receives the fraction done, from 0 to 1, on an arbitrary thread. Values never
    /// go backwards and the last one is 1 when the conversion succeeds. Quick actions (images)
    /// report only that final 1; videos report along the way.
    ///
    /// With `folder`, the output goes there instead of next to the source, under the same
    /// naming rules: for a source that has no place of its own, such as an image dragged out of
    /// a web page and staged in a temporary folder.
    ///
    /// Throws `ConversionError` when the file can't be read, isn't something `action` accepts,
    /// can't be decoded, or the new file can't be written (`.notWritten`, for example on a full
    /// disk); `CancellationError` when the task is cancelled.
    public func convert(
        _ source: URL, with action: some ConversionAction, into folder: URL? = nil,
        progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> ConversionResult {
        try await convert(SourceFile.inspecting(source), with: action, into: folder, progress: progress)
    }

    /// The same, for a file already inspected.
    func convert(
        _ file: SourceFile, with action: some ConversionAction, into folder: URL? = nil,
        progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> ConversionResult {
        activity.begin()
        defer { activity.end() }
        let progress = ConversionProgress(progress)
        guard action.accepts(file) else { throw ConversionError.refusal(of: file, by: action) }
        let placement = Placement(of: file.url, in: folder, baseName: action.baseName(for: file),
                                  fileExtension: action.fileExtension(for: file),
                                  fallback: downloads)
        let output: URL
        do {
            output = try await placement.place { temporary in
                try await action.perform(file, writingTo: temporary, progress: progress)
            }
        } catch let error as ConversionError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Writing failed: no room, no permission, an encoder missing, …
            let detail = (error as? POSIXError).map { String(cString: strerror($0.code.rawValue)) }
                ?? error.localizedDescription
            throw ConversionError.notWritten(file.url, format: action.format, detail: detail)
        }
        progress.report(1)
        return ConversionResult(source: file.url, output: output, savedToDownloads: placement.usesFallback,
                                kind: file.kind, format: action.format)
    }
}
