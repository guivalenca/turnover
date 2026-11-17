import AppKit
import FinderSync
import Observation
import ServiceManagement
import TurnoverKit
import UserNotifications

/// What the Turnover window shows: the setup steps' live status and the two settings.
///
/// The statuses change outside the app (in System Settings), so they're read again every second
/// while the window is open.
@MainActor
@Observable
final class WindowModel {
    enum Notifications {
        /// Not read yet.
        case unknown
        /// The app hasn't asked yet, so System Settings doesn't list it.
        case notAsked
        case allowed
        /// Turned off in System Settings.
        case off
    }

    private(set) var finderExtensionIsOn = false
    private(set) var notifications = Notifications.unknown
    private(set) var opensAtLogin = false

    /// The default JPEG quality. Right-click JPEG reads it from `AppSettings` at each conversion.
    var jpegQuality = AppSettings().jpegQuality {
        didSet {
            guard jpegQuality != oldValue else { return }
            var settings = AppSettings()
            settings.jpegQuality = jpegQuality
        }
    }

    @ObservationIgnored private var watching: Task<Void, Never>?

    /// Keeps the statuses current until `stopWatching()`.
    func startWatching() {
        jpegQuality = AppSettings().jpegQuality
        guard watching == nil else { return }
        watching = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stopWatching() {
        watching?.cancel()
        watching = nil
    }

    func refresh() async {
        finderExtensionIsOn = FIFinderSyncController.isExtensionEnabled
        opensAtLogin = SMAppService.mainApp.status == .enabled
        notifications = switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .notDetermined: .notAsked
        case .authorized, .provisional: .allowed
        default: .off
        }
    }

    // MARK: Actions

    /// System Settings › General › Login Items & Extensions, where Finder extensions are turned on.
    func openFinderExtensionSettings() {
        FIFinderSyncController.showExtensionManagementInterface()
    }

    /// Asks the first time (the system's prompt), then opens Turnover's page in System Settings ›
    /// Notifications.
    func turnOnNotifications() {
        switch notifications {
        case .notAsked:
            Task {
                do {
                    _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                } catch {
                    log.error("Couldn't ask to send notifications: \(error.localizedDescription, privacy: .public)")
                }
                await refresh()
            }
        case .unknown, .allowed, .off:
            let page = "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(Bundle.main.bundleIdentifier ?? "")"
            NSWorkspace.shared.open(URL(string: page)!)
        }
    }

    func setOpensAtLogin(_ on: Bool) {
        let loginItem = SMAppService.mainApp
        do {
            if on { try loginItem.register() } else { try loginItem.unregister() }
        } catch {
            log.error("Couldn't turn Open at login \(on ? "on" : "off"): \(error.localizedDescription, privacy: .public)")
        }
        // Turned off in System Settings › Login Items earlier: only the user can turn it back on.
        if on, loginItem.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
        opensAtLogin = loginItem.status == .enabled
    }
}

extension SMAppService: @retroactive LoginItem {
    public var isEnabled: Bool { status == .enabled }
    public func enable() throws { try register() }
}
