import Foundation
import TurnoverKit

/// Turnover.app's settings, stored in a user defaults domain (the app's own, `.standard`).
///
/// Named so it doesn't clash with SwiftUI's `Settings` scene in the app.
public struct AppSettings {
    /// The default JPEG quality, stored as `JPEGQuality.rawValue` ("best", "high" or "small").
    public static let jpegQualityKey = "jpegQuality"

    let defaults: UserDefaults

    public init(_ defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The default JPEG quality: what right-click JPEG converts with, and what the ring offers.
    /// High until one is chosen.
    public var jpegQuality: JPEGQuality {
        get { defaults.string(forKey: Self.jpegQualityKey).flatMap(JPEGQuality.init(rawValue:)) ?? .default }
        set { defaults.set(newValue.rawValue, forKey: Self.jpegQualityKey) }
    }
}
