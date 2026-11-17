import AppKit
import TurnoverKit
import UserNotifications
import TurnoverAppCore

/// Posts `Feedback`'s notices as notifications. Show in Finder (or a click on the notification)
/// selects the notice's files in Finder.
///
/// It asks for permission the first time it has something to post. Make it before the app
/// finishes launching, so a click that launches the app reaches it.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private nonisolated static let showCategory = "show-in-finder"
    private nonisolated static let showAction = "show-in-finder"
    private nonisolated static let filesKey = "files"

    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
        let show = UNNotificationAction(identifier: Self.showAction, title: "Show in Finder")
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.showCategory, actions: [show], intentIdentifiers: [])
        ])
    }

    func post(_ notice: Notice) {
        let content = UNMutableNotificationContent()
        content.title = notice.title
        content.body = notice.body
        content.threadIdentifier = "\(notice.kind)"
        if !notice.files.isEmpty {
            content.categoryIdentifier = Self.showCategory
            content.userInfo = [Self.filesKey: notice.files.map(\.path)]
        }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        Task {
            guard await isAllowed() else {
                log.notice("Notifications are off; not posting “\(notice.title, privacy: .public)”")
                return
            }
            do {
                try await center.add(request)
            } catch {
                log.error("Couldn't post a notification: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func isAllowed() async -> Bool {
        switch NotificationPermission(await center.notificationSettings().authorizationStatus) {
        case .notAsked:
            do {
                return try await center.requestAuthorization(options: NotificationPermission.requestedOptions)
            } catch {
                log.error("Couldn't ask to post notifications: \(error.localizedDescription, privacy: .public)")
                return false
            }
        case .allowed:
            return true
        case .off:
            return false
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        guard [Self.showAction, UNNotificationDefaultActionIdentifier].contains(response.actionIdentifier),
              let paths = response.notification.request.content.userInfo[Self.filesKey] as? [String]
        else { return }
        let files = paths.map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !files.isEmpty else { return }
        await MainActor.run { NSWorkspace.shared.activateFileViewerSelecting(files) }
    }

    /// Notifications show even while the app is frontmost (its window is open).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}
