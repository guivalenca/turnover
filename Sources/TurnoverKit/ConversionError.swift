import Foundation

/// Why a file could not be converted. `errorDescription` is a short reason fit for a terminal
/// line or a notification.
public enum ConversionError: Error, Sendable, Equatable {
    /// The file is missing or can't be read.
    case unreadable(URL)
}

extension ConversionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unreadable(let url):
            "\(url.lastPathComponent): can't be read"
        }
    }
}
