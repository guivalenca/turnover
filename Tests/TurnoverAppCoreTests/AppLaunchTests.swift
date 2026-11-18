import Foundation
import Testing
import TurnoverKit
import TurnoverAppCore

/// When Turnover's window opens at launch. The signals are what AppKit hands
/// `applicationDidFinishLaunching`: its "default launch" flag and the launch Apple event.
@Suite struct AppLaunchTests {
    @Test func openingTheAppFromFinderOrSpotlightOpensTheWindow() {
        let launch = AppLaunch(isDefaultLaunch: true, event: .openApplication())

        #expect(launch.opensWindow)
    }

    /// The Finder menu launched the app to convert: `application(_:open:)` came first, and
    /// AppKit reports a launch that isn't the default one.
    @Test func launchingToConvertFromTheFinderMenuStaysWindowless() {
        let launch = AppLaunch(isDefaultLaunch: false, event: nil)

        #expect(!launch.opensWindow)
    }

    @Test func openingAtLoginStaysWindowless() {
        let launch = AppLaunch(isDefaultLaunch: true, event: .openApplication(asLoginItem: true))

        #expect(!launch.opensWindow)
    }
}

extension NSAppleEventDescriptor {
    /// The `aevt/oapp` event LaunchServices launches an app with. At login, its `keyAEPropData`
    /// parameter is `keyAELaunchedAsLogInItem`.
    static func openApplication(asLoginItem: Bool = false) -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor.appleEvent(
            withEventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEOpenApplication),
            targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID))
        if asLoginItem {
            event.setParam(
                NSAppleEventDescriptor(enumCode: OSType(keyAELaunchedAsLogInItem)),
                forKeyword: AEKeyword(keyAEPropData))
        }
        return event
    }
}
