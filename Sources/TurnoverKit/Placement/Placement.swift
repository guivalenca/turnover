import Darwin
import Foundation

/// Where and how an output file appears: in `folder`, under the name the action gives
/// (the source's, mostly) with the new extension, numbered Finder-style on a collision (`photo 2.png`, `photo 3.png`, …), with the
/// source's creation and modification dates. `folder` is the source's own folder, or the one
/// asked for (an image dragged out of a web page has no folder of its own: the drop says where
/// it goes), or the fallback (Downloads) when that folder can't be written to.
///
/// The output is written to a private temporary folder on the same volume, then moved into
/// place with an exclusive rename, so it appears whole or not at all and never replaces a file,
/// even one created by someone else at the same moment.
struct Placement {
    let source: URL
    let folder: URL
    let baseName: String
    let fileExtension: String
    /// Whether `folder` is the fallback rather than the folder wanted.
    let usesFallback: Bool

    /// Next to `source`, or in `destination` when one is given.
    init(of source: URL, in destination: URL? = nil, baseName: String, fileExtension: String, fallback: URL) {
        self.source = source
        let wanted = destination ?? source.deletingLastPathComponent()
        // Asked up front: a read-only disk image fails the final rename with EXDEV, not EROFS,
        // because the temporary folder can't be made on it and lands on the startup disk.
        usesFallback = access(wanted.path, W_OK) != 0
        folder = usesFallback ? fallback : wanted
        self.baseName = baseName
        self.fileExtension = fileExtension
    }

    /// Runs `write` against a temporary file, then moves the result into place and returns
    /// its final URL. Whatever happens, the temporary folder is removed. If the task is
    /// cancelled, nothing is moved into place and this throws `CancellationError`.
    func place(_ write: (URL) async throws -> Void) async throws -> URL {
        let scratch = try makeScratchFolder()
        defer { try? FileManager.default.removeItem(at: scratch) }

        let temporary = scratch.appendingPathComponent(name(number: 1))
        try await write(temporary)
        try copyDates(to: temporary)
        try Task.checkCancellation()
        return try moveIntoPlace(temporary)
    }

    /// A private temporary folder on `folder`'s volume, so the final rename can be atomic.
    ///
    /// Usually that is the volume's own temporary-items folder. Where macOS can't make one there
    /// (a share or drive whose top level the user can't write to) or hands back one on another
    /// volume (some network shares), it is a hidden folder inside `folder` itself.
    private func makeScratchFolder() throws -> URL {
        let fileManager = FileManager.default
        if let system = try? fileManager.url(
            for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: folder, create: true) {
            if let device = Self.device(of: system), device == Self.device(of: folder) { return system }
            try? fileManager.removeItem(at: system)
        }
        let hidden = folder.appendingPathComponent(".turnover-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: hidden, withIntermediateDirectories: false)
        return hidden
    }

    private static func device(of url: URL) -> dev_t? {
        var info = stat()
        return stat(url.path, &info) == 0 ? info.st_dev : nil
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
