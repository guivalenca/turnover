import Foundation

/// A small blank disk image, mounted for one test like an external drive. It is mounted with
/// `-nobrowse`, so Finder doesn't show it.
///
///     try await DiskImage.withMounted { disk in
///         let album = try disk.folder("Album")
///         …
///     }
public final class DiskImage: Sendable {
    /// Where the volume is mounted.
    public let volume: URL

    private init(volume: URL) {
        self.volume = volume
    }

    /// Mounts a fresh image, runs `body` with it, then ejects and deletes it.
    ///
    /// `hdiutil` can take many seconds on a loaded CI machine, so it is awaited rather than
    /// waited for: blocking would hold one of the few threads every other test shares.
    public static func withMounted<Result>(_ body: (DiskImage) async throws -> Result) async throws -> Result {
        let scratch = try ScratchFolder()
        let image = scratch.url.appendingPathComponent("disk.dmg")
        let disk = DiskImage(volume: scratch.url.appendingPathComponent("Volume", isDirectory: true))
        try FileManager.default.createDirectory(at: disk.volume, withIntermediateDirectories: false)
        try await hdiutil("create", "-quiet", "-size", "16m", "-fs", "APFS", "-volname", "Turnover Test", image.path)
        try await hdiutil("attach", "-quiet", "-nobrowse", "-noautoopen", "-mountpoint", disk.volume.path, image.path)

        let result: Swift.Result<Result, any Error>
        do { result = .success(try await body(disk)) } catch { result = .failure(error) }

        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: disk.volume.path)
        if (try? await hdiutil("detach", "-quiet", disk.volume.path)) == nil {
            try await hdiutil("detach", "-quiet", "-force", disk.volume.path)
        }
        return try result.get()
    }

    /// Makes a folder on the volume and returns it.
    public func folder(_ name: String) throws -> URL {
        let folder = volume.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Leaves the volume like a share or a shared drive whose top level the user can't write to,
    /// though folders inside are writable: macOS then can't make its temporary-items folder on
    /// the volume, and `FileManager`'s item-replacement folder fails with "permission denied".
    public func lockTopLevel() throws {
        try Data().write(to: volume.appendingPathComponent(".TemporaryItems"))
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: volume.path)
    }

    private static func hdiutil(_ arguments: String...) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = arguments
        let status = try await withCheckedThrowingContinuation { (done: CheckedContinuation<Int32, any Error>) in
            process.terminationHandler = { done.resume(returning: $0.terminationStatus) }
            do { try process.run() } catch { done.resume(throwing: error) }
        }
        guard status == 0 else {
            throw CocoaError(.fileWriteUnknown, userInfo: [
                NSLocalizedDescriptionKey: "hdiutil \(arguments.joined(separator: " ")) exited \(status)",
            ])
        }
    }
}
