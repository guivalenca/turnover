import AppKit
import ServiceManagement
import TurnoverKit
import TurnoverAppCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Every conversion the app runs, whoever asked for it.
    let conversions = Conversions()
    let window = TurnoverWindow()
    /// The drag + ⇧ ring.
    private lazy var ring = Ring(conversions: conversions)

    func applicationDidFinishLaunching(_ notification: Notification) {
        log.notice("Launched from \(Bundle.main.bundlePath, privacy: .public)")
        MainMenu.install()
        do {
            try AppSettings().turnOnOpenAtLoginOnFirstLaunch(SMAppService.mainApp)
        } catch {
            log.error("Couldn't turn Open at login on: \(error.localizedDescription, privacy: .public)")
        }
        ring.start()
        let launch = AppLaunch(
            isDefaultLaunch: notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool ?? true,
            event: NSAppleEventManager.shared().currentAppleEvent)
        if launch.opensWindow, !RingPreview.isRunning { window.show() }
    }

    /// Turnover opened again (Finder, Spotlight, `open`) while it runs.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        window.show()
        return false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    /// The Finder extension's requests arrive here as `turnover://convert?…` URLs. LaunchServices
    /// launches the app first if it isn't running. Any process can open such a URL, so each one
    /// is checked before anything is converted.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            do {
                conversions.convert(try ConversionRequest(url))
            } catch {
                log.error("\(error.description, privacy: .public)")
            }
        }
    }
}
