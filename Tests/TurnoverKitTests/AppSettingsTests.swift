import Foundation
import Testing
import TurnoverKit

@Suite struct AppSettingsTests {
    /// A defaults domain of its own, as a fresh install has.
    let defaults = FreshDefaults()

    @Test func jpegQualityIsHighUntilChosen() {
        #expect(AppSettings(defaults.store).jpegQuality == .high)
    }

    @Test(arguments: [JPEGQuality.best, .high, .small])
    func aChosenJPEGQualityIsKeptForTheNextLaunch(quality: JPEGQuality) {
        var settings = AppSettings(defaults.store)
        settings.jpegQuality = quality

        #expect(AppSettings(defaults.store).jpegQuality == quality)
    }

    @Test func anUnknownStoredQualityReadsAsHigh() {
        defaults.store.set("medium", forKey: AppSettings.jpegQualityKey)

        #expect(AppSettings(defaults.store).jpegQuality == .high)
    }

    // MARK: Open at login

    @Test func theFirstLaunchTurnsOpenAtLoginOn() throws {
        let loginItem = FakeLoginItem()

        try AppSettings(defaults.store).turnOnOpenAtLoginOnFirstLaunch(loginItem)

        #expect(loginItem.isEnabled)
    }

    @Test func laterLaunchesLeaveOpenAtLoginOffOnceTheUserTurnedItOff() throws {
        let loginItem = FakeLoginItem()
        try AppSettings(defaults.store).turnOnOpenAtLoginOnFirstLaunch(loginItem)
        loginItem.isEnabled = false  // the switch, or System Settings › Login Items

        try AppSettings(defaults.store).turnOnOpenAtLoginOnFirstLaunch(loginItem)

        #expect(!loginItem.isEnabled)
    }

    @Test func aLaunchThatFailedToTurnItOnTriesAgainNextTime() throws {
        let loginItem = FakeLoginItem()
        loginItem.refusesNext = true
        #expect(throws: FakeLoginItem.Refused.self) {
            try AppSettings(defaults.store).turnOnOpenAtLoginOnFirstLaunch(loginItem)
        }

        try AppSettings(defaults.store).turnOnOpenAtLoginOnFirstLaunch(loginItem)

        #expect(loginItem.isEnabled)
    }
}

/// Stands in for `SMAppService.mainApp`, the system's login item for the app.
final class FakeLoginItem: LoginItem {
    struct Refused: Error {}

    var isEnabled = false
    /// The next `enable()` throws, as `SMAppService.register()` can.
    var refusesNext = false

    func enable() throws {
        if refusesNext {
            refusesNext = false
            throw Refused()
        }
        isEnabled = true
    }
}

/// A new, empty user defaults domain, removed when the test ends.
final class FreshDefaults {
    let name = "com.guivalenca.turnover.tests.\(UUID().uuidString)"
    let store: UserDefaults

    init() { store = UserDefaults(suiteName: name)! }
    deinit { store.removePersistentDomain(forName: name) }
}
