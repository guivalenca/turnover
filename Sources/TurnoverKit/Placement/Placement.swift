import Darwin
import Foundation

/// Where and how an output file appears: in `folder`, named after the source with the new
/// extension, numbered Finder-style on a collision (`photo 2.png`, `photo 3.png`, …), with the
/// source's creation and modification dates. `folder` is the source's own folder, or the
/// fallback (Downloads) when the source's folder can't be written to.
///
/// The output is written to a private temporary folder on the same volume, then moved into
/// place with an exclusive rename, so it appears whole or not at all and never replaces a file,
/// even one created by someone else at the same moment.
struct Placement {
    let source: URL
    let folder: URL
    let baseName: String
    let fileExtension: String
    /// Whether `folder` is the fallback rather than the source's folder.
    let usesFallback: Bool

    init(nextTo source: URL, fileExtension: String, fallback: URL) {
        self.source = source
        let sourceFolder = source.deletingLastPathComponent()
        // Asked up front: a read-only disk image fails the final rename with EXDEV, not EROFS,
        // because the temporary folder can't be made on it and lands on the startup disk.
        usesFallback = access(sourceFolder.path, W_OK) != 0
        folder = usesFallback ? fallback : sourceFolder
        baseName = source.deletingPathExtension().lastPathComponent
        self.fileExtension = fileExtension
    }

    /// Runs `write` against a temporary file, then moves the result into place and returns
    /// its final URL. Whatever happens, the temporary folder is removed. If the task is
    /// cancelled, nothing is moved into place and this throws `CancellationError`.
    func place(_ write: (URL) async throws -> Void) async throws -> URL {
        let fileManager = FileManager.default
        let scratch = try fileManager.url(
            for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: folder, create: true)
        defer { try? fileManager.removeItem(at: scratch) }

        let temporary = scratch.appendingPathComponent(name(number: 1))
        try await write(temporary)
        try copyDates(to: temporary)
        try Task.checkCancellation()
        return try moveIntoPlace(temporary)
    }

    /// Stamps the source's creation and modification dates on `file`. A rename keeps them.
    private func copyDates(to file: URL) throws {
        let dates = try source.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        var attributes: [FileAttributeKey: Any] = [:]
        attributes[.creationDate] = dates.creationDate
        attributes[.modificationDate] = dates.contentModificationDate
        try FileManager.default.setAttributes(attributes, ofItemAtPath: file.path)
    }

    /// `photo.png`, then `photo 2.png`, `photo 3.png`, …
    func name(number: Int) -> String {
        let base = number == 1 ? baseName : "\(baseName) \(number)"
        return "\(base).\(fileExtension)"
    }

    private func moveIntoPlace(_ temporary: URL) throws -> URL {
        for number in 1... {
            let candidate = folder.appendingPathComponent(name(number: number))
            if renamex_np(temporary.path, candidate.path, UInt32(RENAME_EXCL)) == 0 { return candidate }
            guard errno == EEXIST else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        }
        fatalError("unreachable")
    }
}
