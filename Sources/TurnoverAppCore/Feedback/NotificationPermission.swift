import UserNotifications

/// Whether Turnover may post notifications, read from the system's setting. The window's setup
/// row and the notifier both read it this way, and both ask with `requestedOptions`.
public enum NotificationPermission: Sendable, Hashable {
    /// Not asked yet, so System Settings doesn't list Turnover. Asking shows the system's prompt.
    case notAsked
    /// Notifications are delivered, perhaps quietly (provisional).
    case allowed
    /// Turned off in System Settings.
    case off

    public init(_ status: UNAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notAsked
        case .denied: self = .off
        // A status macOS adds later is most likely a way of delivering, like provisional; the
        // system still decides whether a notice shows.
        case .authorized, .provisional: self = .allowed
        @unknown default: self = .allowed
        }
    }

    /// What Turnover asks for: banners only. No notice plays a sound or sets a badge.
    public static let requestedOptions: UNAuthorizationOptions = [.alert]
}
