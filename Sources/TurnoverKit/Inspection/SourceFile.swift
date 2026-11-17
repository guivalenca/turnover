import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A file the user asked to convert, classified by its contents, never by its extension.
public struct SourceFile: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        /// Anything ImageIO can decode as a picture (HEIC, JPEG, PNG, WebP, AVIF, TIFF, …).
        case image
        /// A QuickTime or MPEG-4 movie.
        case video
        /// Anything else, including documents ImageIO happens to render, such as PDF.
        case unsupported
    }

    public let url: URL
    public let kind: Kind
    /// The detected format. For unsupported files it is a best guess, for naming them in messages.
    public let contentType: UTType

    /// Inspects the file at `url`. Throws `ConversionError.unreadable` if it can't be read.
    public init(_ url: URL) throws {
        self.url = url
        guard let header = Self.readHeader(url) else { throw ConversionError.unreadable(url) }
        if let type = Self.imageType(url) {
            (kind, contentType) = (.image, type)
        } else if let type = Self.movieType(header) {
            (kind, contentType) = (.video, type)
        } else {
            kind = .unsupported
            contentType = Self.anyImageIOType(url)
                ?? UTType(filenameExtension: url.pathExtension)
                ?? .data
        }
    }

    private static func readHeader(_ url: URL) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 16)) ?? Data()
    }

    /// ImageIO sniffs the bytes. Only picture formats count: ImageIO also renders PDFs.
    private static func imageType(_ url: URL) -> UTType? {
        guard let type = anyImageIOType(url), type.conforms(to: .image) else { return nil }
        return type
    }

    private static func anyImageIOType(_ url: URL) -> UTType? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let identifier = CGImageSourceGetType(source)
        else { return nil }
        return UTType(identifier as String)
    }

    /// QuickTime and MPEG-4 files are ISO base media files: a sequence of boxes, usually starting
    /// with `ftyp`, whose major brand says which. Old QuickTime files may start with another atom.
    private static func movieType(_ header: Data) -> UTType? {
        guard header.count >= 12 else { return nil }
        let bytes = [UInt8](header)
        let box = String(decoding: bytes[4..<8], as: UTF8.self)
        guard box == "ftyp" else {
            return ["moov", "mdat", "wide", "free", "skip", "pnot"].contains(box) ? .quickTimeMovie : nil
        }
        switch String(decoding: bytes[8..<12], as: UTF8.self) {
        case "qt  ": return .quickTimeMovie
        case "M4V ", "M4VH", "M4VP": return UTType("com.apple.m4v-video") ?? .mpeg4Movie
        case "M4A ", "M4B ", "M4P ", "F4A ", "F4B ": return nil  // audio only
        default: return .mpeg4Movie
        }
    }
}
