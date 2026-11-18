import Foundation

/// Why a file could not be converted. `errorDescription` is a short reason that starts with the
/// file's name, fit for a terminal line or a notification: "x.heic: can't be read".
public enum ConversionError: Error, Sendable, Hashable {
    /// The file is missing or can't be read.
    case unreadable(URL)
    /// The file looks like an image or video but can't be decoded: truncated or corrupt.
    case damaged(URL)
    /// The file is neither an image nor a video. `typeDescription` names what it is, e.g. "PDF document".
    case unsupported(URL, typeDescription: String)
    /// The file is already in the requested format, e.g. a PNG asked to become a PNG.
    case alreadyInFormat(URL, format: OutputFormat)
    /// The action doesn't take this kind of file, e.g. a video asked to become a PNG.
    case notApplicable(URL, format: OutputFormat)
    /// The new file couldn't be written: no room, no permission, …. `detail` is the system's
    /// reason, e.g. "Permission denied".
    case notWritten(URL, format: OutputFormat, detail: String)

    /// The file that couldn't be converted.
    public var file: URL {
        switch self {
        case .unreadable(let url), .damaged(let url), .unsupported(let url, _), .alreadyInFormat(let url, _),
             .notApplicable(let url, _), .notWritten(let url, _, _):
            url
        }
    }

    /// Why, without the file's name: "damaged or incomplete, can't be decoded".
    public var reason: String {
        switch self {
        case .unreadable:
            String(localized: "can't be read", bundle: .turnoverKit,
                   comment: "Why a file wasn't converted, after its name: “x.heic: can't be read”.")
        case .damaged:
            String(localized: "damaged or incomplete, can't be decoded", bundle: .turnoverKit,
                   comment: "Why a file wasn't converted, after its name.")
        case .unsupported(_, let typeDescription):
            String(localized: "not an image or a video (\(typeDescription))", bundle: .turnoverKit,
                   comment: "Why a file wasn't converted, after its name. The file's type: “PDF document”.")
        case .alreadyInFormat(_, .png):
            String(localized: "already a PNG", bundle: .turnoverKit, comment: "Why a file wasn't converted, after its name.")
        case .alreadyInFormat(_, .jpeg):
            String(localized: "already a JPEG", bundle: .turnoverKit, comment: "Why a file wasn't converted, after its name.")
        case .alreadyInFormat(_, .mp4):
            String(localized: "already an MP4", bundle: .turnoverKit, comment: "Why a file wasn't converted, after its name.")
        // `.alreadyInFormat` with `original` never happens: every image can be saved as it is.
        case .notApplicable(_, let format), .alreadyInFormat(_, let format):
            String(localized: "can't be converted to \(format.name)", bundle: .turnoverKit,
                   comment: "Why a file wasn't converted, after its name. The format: “PNG”.")
        case .notWritten(_, let format, let detail):
            String(localized: "couldn't write the \(format.name) (\(detail))", bundle: .turnoverKit,
                   comment: "Why a file wasn't converted, after its name. The format, then the system's reason: “couldn't write the PNG (Permission denied)”.")
        }
    }
}

extension ConversionError {
    /// Why `action` doesn't take `file`.
    static func refusal(of file: SourceFile, by action: any ConversionAction) -> ConversionError {
        if file.kind == .unsupported {
            return .unsupported(file.url, typeDescription: file.contentType.localizedDescription ?? file.contentType.identifier)
        }
        if file.contentType.conforms(to: action.outputType) {
            return .alreadyInFormat(file.url, format: action.format)
        }
        return .notApplicable(file.url, format: action.format)
    }
}

extension ConversionError: LocalizedError {
    public var errorDescription: String? {
        String(localized: "\(file.lastPathComponent): \(reason)", bundle: .turnoverKit,
               comment: "A file's name, then why it wasn't converted: “x.heic: can't be read”.")
    }
}
