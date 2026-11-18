import Foundation
import UniformTypeIdentifiers

/// An image dragged as a picture rather than as a file: out of a web page, mostly. Safari and
/// Chrome both put the image's own bytes on the drag pasteboard under its type
/// ("org.webmproject.webp", "public.jpeg"), next to a promise of a file, its address and its
/// title. Read from what the pasteboard lists, without touching the bytes.
public struct DraggedImage: Sendable, Equatable {
    /// The pasteboard type that holds the image's bytes.
    public let pasteboardType: String
    /// What those bytes are said to be. The file is inspected again once it is staged.
    public let contentType: UTType
    /// The name to save it under, without an extension: from its address when that names an
    /// image file, else from its title, else "image".
    public let name: String

    /// The name of the file it is staged as: "mountain-lake.webp". JPEG takes "jpg", the
    /// extension people expect.
    public var fileName: String {
        let fileExtension = contentType.conforms(to: .jpeg) ? "jpg" : contentType.preferredFilenameExtension ?? "img"
        return "\(name).\(fileExtension)"
    }

    /// The image a drag pasteboard holding `types` carries, or nil when it carries none: a drag
    /// of files (those are converted where they are), of text or a link, or of a promised file
    /// whose bytes aren't on the pasteboard.
    ///
    /// - Parameters:
    ///   - promisedType: The promised file's type ("com.apple.pasteboard.promised-file-content-type"),
    ///     if any. When the bytes are there under it, that is the image as the page has it.
    ///     Otherwise any image type will do, TIFF last: Safari also offers the decoded picture
    ///     as TIFF, which is much larger and no longer the original.
    ///   - url: The dragged address. For an image inside a link it is the link's, not the image's.
    ///   - title: The dragged title, usually the image's alternative text.
    public init?(types: [String], promisedType: String? = nil, url: String? = nil, title: String? = nil) {
        guard !types.contains(UTType.fileURL.identifier) else { return nil }
        let images = types.compactMap { type -> (String, UTType)? in
            guard let content = UTType(type), content != .image, content.conforms(to: .image) else { return nil }
            return (type, content)
        }
        guard let (type, content) = images.first(where: { $0.0 == promisedType })
            ?? images.first(where: { !$0.1.conforms(to: .tiff) })
            ?? images.first
        else { return nil }
        pasteboardType = type
        contentType = content
        name = Self.name(url: url, title: title)
    }

    private static func name(url: String?, title: String?) -> String {
        if let url, let address = URL(string: url), ["http", "https"].contains(address.scheme?.lowercased()) {
            let last = address.lastPathComponent as NSString
            if UTType(filenameExtension: last.pathExtension)?.conforms(to: .image) == true {
                let name = cleaned(last.deletingPathExtension)
                if !name.isEmpty { return name }
            }
        }
        if let title, !title.contains("://") {
            let name = cleaned(title)
            if !name.isEmpty { return name }
        }
        return String(localized: "image", bundle: .appCore,
                      comment: "The name of the file an image dragged out of a web page is saved as, when neither its address nor its title gives one: “image.png”.")
    }

    /// `text` as a file name: nothing a path can't hold, one space between words, no leading
    /// dot, and not too long.
    private static func cleaned(_ text: String) -> String {
        let unsafe = CharacterSet(charactersIn: "/:\\").union(.controlCharacters).union(.newlines)
        let words = text.components(separatedBy: unsafe).joined(separator: " ")
            .split(whereSeparator: \.isWhitespace)
        var name = String(words.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: ". ")).prefix(80))
        // A file name holds 255 bytes, extension and a number included; some characters take many.
        while name.utf8.count > 200 { name.removeLast() }
        return name.trimmingCharacters(in: .whitespaces)
    }
}
