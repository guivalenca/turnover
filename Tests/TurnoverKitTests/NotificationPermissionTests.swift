import Testing
import TurnoverKit
import UserNotifications

/// What the system's notification setting means for Turnover. The window's setup row and the
/// notifier both read it this way, and ask for the same thing.
@Suite struct NotificationPermissions {
    @Test(arguments: [
        (UNAuthorizationStatus.notDetermined, NotificationPermission.notAsked),
        (.authorized, .allowed),
        (.provisional, .allowed),
        (.denied, .off),
    ])
    func eachSystemStatusMeansOneThing(status: UNAuthorizationStatus, permission: NotificationPermission) {
        #expect(NotificationPermission(status) == permission)
    }

    /// Banners only: no notice plays a sound or sets a badge.
    @Test func turnoverAsksForBannersOnly() {
        #expect(NotificationPermission.requestedOptions == [.alert])
    }
}
