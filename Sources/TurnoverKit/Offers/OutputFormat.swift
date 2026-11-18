import Foundation

/// A format Turnover can convert files to. The raw values ("png", "jpeg", "mp4") are what
/// `turnover --to` takes (the command reads them from here), so they are stable enough to pass
/// between processes. Adding a case adds the format everywhere: the command, the Finder menu
/// and the ring.
public enum OutputFormat: String, CaseIterable, Sendable, Hashable {
    case png
    case jpeg
    case mp4
    /// Not a conversion: the image as it is. Offered only for an image that has no file of its
    /// own yet, one dragged out of a web page, so that it can be saved unchanged next to PNG and
    /// JPEG. A file on disk is never offered it, and neither the command nor a request takes it.
    case original

    /// The formats files are converted to: every case but `original`.
    public static let allCases: [OutputFormat] = [.png, .jpeg, .mp4]

    /// The format `name` stands for on a command line or in a request ("png", "jpeg", "mp4");
    /// nil for anything else, `original` included.
    public init?(conversion name: String) {
        guard let format = Self.allCases.first(where: { $0.rawValue == name }) else { return nil }
        self = format
    }

    /// The short name users see: "PNG", "JPEG", "MP4" or "Original".
    public var name: String {
        switch self {
        case .png: "PNG"
        case .jpeg: "JPEG"
        case .mp4: "MP4"
        case .original:
            String(localized: "Original", bundle: .turnoverKit,
                   comment: "The ring's entry that saves an image dragged out of a web page as it is, next to PNG and JPEG.")
        }
    }

    /// The action that converts to this format. `quality` applies to JPEG only: the default
    /// preset when nil.
    public func action(quality: JPEGQuality? = nil) -> any ConversionAction {
        switch self {
        case .png: PNGAction()
        case .jpeg: JPEGAction(quality: quality ?? .default)
        case .mp4: MP4Action()
        case .original: OriginalAction()
        }
    }
}
