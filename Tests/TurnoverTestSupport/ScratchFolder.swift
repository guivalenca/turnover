import Foundation

/// A fresh, empty temporary folder for one test, deleted when the value goes away.
/// Copy fixtures in, convert them there, and look at what appeared.
public final class ScratchFolder: @unchecked Sendable {
    public let url: URL

    public init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TurnoverTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        try? FileManager.default.removeItem(at: url)
    }

    /// Makes the folder read-only, like a disk image or a locked drive: nothing can be added.
    public func makeReadOnly() throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: url.path)
    }

    /// Copies a fixture in, under its own name or `name`, and returns the copy's URL.
    @discardableResult
    public func add(_ fixture: Fixture, as name: String? = nil) throws -> URL {
        let copy = url.appendingPathComponent(name ?? fixture.rawValue)
        try FileManager.default.copyItem(at: fixture.url, to: copy)
        return copy
    }

    /// Writes arbitrary bytes into a new file and returns its URL.
    @discardableResult
    public func add(_ data: Data, as name: String) throws -> URL {
        let file = url.appendingPathComponent(name)
        try data.write(to: file)
        return file
    }

    /// The names in the folder, hidden files included, sorted.
    public func fileNames() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: url.path).sorted()
    }
}
