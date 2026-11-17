/// A format Turnover can convert files to. The raw values ("png", "jpeg", "mp4") are what
/// `turnover --to` takes (the command reads them from here), so they are stable enough to pass
/// between processes. Adding a case adds the format everywhere: the command, the Finder menu
/// and the ring.
public enum OutputFormat: String, CaseIterable, Sendable, Hashable {
    case png
    case jpeg
    case mp4

    /// The short name users see: "PNG", "JPEG" or "MP4".
    public var name: String {
        switch self {
        case .png: "PNG"
        case .jpeg: "JPEG"
        case .mp4: "MP4"
        }
    }

    /// The action that converts to this format. `quality` applies to JPEG only: the default
    /// preset when nil.
    public func action(quality: JPEGQuality? = nil) -> any ConversionAction {
        switch self {
        case .png: PNGAction()
        case .jpeg: JPEGAction(quality: quality ?? .default)
        case .mp4: MP4Action()
        }
    }
}
