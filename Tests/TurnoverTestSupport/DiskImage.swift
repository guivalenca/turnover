import Foundation

/// A small blank disk image, mounted for one test like an external drive, and ejected and
/// deleted when the value goes away. It is mounted with `-nobrowse`, so Finder doesn't show it.
public final class DiskImage: @unchecked Sendable {
    /// Where the volume is mounted.
    public let volume: URL
    private let scratch: ScratchFolder

    public init() throws {
        scratch = try ScratchFolder()
        let image = scratch.url.appendingPathComponent("disk.dmg")
        volume = scratch.url.appendingPathComponent("Volume", isDirectory: true)
        try FileManager.default.createDirectory(at: volume, withIntermediateDirectories: false)
        try Self.hdiutil("create", "-quiet", "-size", "16m", "-fs", "APFS", "-volname", "Turnover Test", image.path)
        try Self.hdiutil("attach", "-quiet", "-nobrowse", "-noautoopen", "-mountpoint", volume.path, image.path)
    }

    deinit {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: volume.path)
        if (try? Self.hdiutil("detach", "-quiet", volume.path)) == nil {
            try? Self.hdiutil("detach", "-quiet", "-force", volume.path)
        }
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

    private static func hdiutil(_ arguments: String...) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CocoaError(.fileWriteUnknown, userInfo: [
                NSLocalizedDescriptionKey: "hdiutil \(arguments.joined(separator: " ")) exited \(process.terminationStatus)",
            ])
        }
    }
}
