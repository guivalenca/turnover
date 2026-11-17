import AppKit
import TurnoverKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Every conversion the app runs, whoever asked for it.
    let conversions = Conversions()

    func applicationDidFinishLaunching(_ notification: Notification) {
        log.notice("Launched from \(Bundle.main.bundlePath, privacy: .public)")
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
