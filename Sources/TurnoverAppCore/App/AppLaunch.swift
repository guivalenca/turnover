import Foundation

/// How Turnover.app was launched, which decides whether its window opens.
///
/// The window opens when someone opens the app: from Finder, Launchpad, Spotlight or `open`,
/// including the first launch. It stays closed when the app opens at login, or when the Finder
/// menu launches it to convert. (Opening the app again while it runs always shows the window;
/// that's `applicationShouldHandleReopen`, not a launch.)
public struct AppLaunch {
    /// Whether the window opens.
    public let opensWindow: Bool

    /// - Parameters:
    ///   - isDefaultLaunch: `NSApplication.launchIsDefaultUserInfoKey` from
    ///     `applicationDidFinishLaunching`. False when the app was launched to open a URL.
    ///   - event: the launch Apple event, `NSAppleEventManager.shared().currentAppleEvent` there.
    ///     At login it's `aevt/oapp` with `keyAEPropData` set to `keyAELaunchedAsLogInItem`.
    public init(isDefaultLaunch: Bool, event: NSAppleEventDescriptor?) {
        let atLogin = event?.eventClass == AEEventClass(kCoreEventClass)
            && event?.eventID == AEEventID(kAEOpenApplication)
            && event?.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue
                == OSType(keyAELaunchedAsLogInItem)
        opensWindow = isDefaultLaunch && !atLogin
    }
}
