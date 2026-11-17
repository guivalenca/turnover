import Foundation
import TurnoverKit

/// The app's stored settings, in its standard user defaults.
enum Settings {
    /// The default JPEG quality, stored as `JPEGQuality.rawValue` ("best", "high" or "small").
    static let jpegQualityKey = "jpegQuality"

    /// The default JPEG quality: what right-click JPEG converts with. High when unset or unknown.
    static var jpegQuality: JPEGQuality {
        UserDefaults.standard.string(forKey: jpegQualityKey).flatMap(JPEGQuality.init(rawValue:)) ?? .default
    }
}
