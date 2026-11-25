import Foundation

/// A format Turnover can convert files to. The raw values ("png", "jpeg", "mp4", "smaller") are what
/// `turnover --to` takes (the command reads them from here), so they are stable enough to pass
/// between processes. Adding a case adds the format everywhere: the command, the Finder menu
/// and the ring.
public enum OutputFormat: String, CaseIterable, Sendable, Hashable {
    case png
    case jpeg
    case mp4
    /// An MP4 made smaller, at a lower quality: for files that are MP4s already.
    case smaller
    /// Not a conversion: the image as it is. Offered only for an image that has no file of its
    /// own yet, one dragged out of a web page, so that it can be saved unchanged next to PNG and
    /// JPEG. A file on disk is never offered it, and neither the command nor a request takes it.
    case original

    /// The formats files are converted to: every case but `original`.
    public static let allCases: [OutputFormat] = [.png, .jpeg, .mp4, .smaller]

    /// The format `name` stands for on a command line or in a request ("png", "jpeg", "mp4", "smaller");
    /// nil for anything else, `original` included.
    public init?(conversion name: String) {
        guard let format = Self.allCases.first(where: { $0.rawValue == name }) else { return nil }
        self = format
    }

    /// The name users see: "PNG", "JPEG", "MP4", "Smaller MP4" or "Original".
    public var name: String {
        switch self {
        case .png: "PNG"
        case .jpeg: "JPEG"
        case .mp4: "MP4"
        case .smaller:
            String(localized: "Smaller MP4", bundle: .turnoverKit,
                   comment: "The format that makes an MP4 smaller, at a lower quality: “Smaller MP4 (2 videos)” in the Finder menu.")
        case .original:
            String(localized: "Original", bundle: .turnoverKit,
                   comment: "The ring's entry that saves an image dragged out of a web page as it is, next to PNG and JPEG.")
        }
    }

    /// The name on the ring, where there is little room: "Smaller" for "Smaller MP4".
    public var shortName: String {
        guard self == .smaller else { return name }
        return String(localized: "Smaller", bundle: .turnoverKit,
                      comment: "The ring's entry that makes an MP4 smaller, at a lower quality.")
    }

    /// The action that converts to this format. `quality` applies to the formats that have
    /// `qualities`: the default one when nil, or when it is another format's.
    public func action(quality: Quality? = nil) -> any ConversionAction {
        switch self {
        case .png: PNGAction()
        case .jpeg:
            if case .jpeg(let quality) = quality { JPEGAction(quality: quality) } else { JPEGAction() }
        case .mp4: MP4Action()
        case .smaller:
            if case .video(let quality) = quality { SmallerAction(quality: quality) } else { SmallerAction() }
        case .original: OriginalAction()
        }
    }
}
