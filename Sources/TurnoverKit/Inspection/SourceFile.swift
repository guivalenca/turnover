import Foundation
import UniformTypeIdentifiers

/// A file the user asked to convert, with its type as detected from its contents.
public struct SourceFile: Sendable, Hashable {
    public let url: URL

    public init(_ url: URL) {
        self.url = url
    }
}
