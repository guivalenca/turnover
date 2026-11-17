import Foundation

/// Why a file could not be converted. `errorDescription` is a short reason fit for a terminal
/// line or a notification.
public enum ConversionError: Error, Sendable, Equatable {
    /// The file is missing or can't be read.
    case unreadable(URL)
    /// The file looks like an image or video but can't be decoded: truncated or corrupt.
    case damaged(URL)
    /// The file is neither an image nor a video. `typeDescription` names what it is, e.g. "PDF document".
    case unsupported(URL, typeDescription: String)
    /// The file is already in the requested format, e.g. a PNG asked to become a PNG.
    case alreadyInFormat(URL, format: String)
    /// The action doesn't take this kind of file, e.g. a video asked to become a PNG.
    case notApplicable(URL, format: String)
}

extension ConversionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unreadable(let url):
            "\(url.lastPathComponent): can't be read"
        case .damaged(let url):
            "\(url.lastPathComponent): damaged or incomplete, can't be decoded"
        case .unsupported(let url, let typeDescription):
            "\(url.lastPathComponent): not an image or a video (\(typeDescription))"
        case .alreadyInFormat(let url, let format):
            "\(url.lastPathComponent): already a \(format)"
        case .notApplicable(let url, let format):
            "\(url.lastPathComponent): can't be converted to \(format)"
        }
    }
}
