// Throwaway spike for ticket #2: an LSUIElement agent that
//  - watches for a drag from another app and ⇧ pressed mid-drag (DragWatcher.swift),
//  - shows a full-screen drop panel mid-drag (RingPanel.swift),
//  - receives conversion requests from the Finder Sync extension over a URL scheme (below).
// Everything is logged with os_log, subsystem com.guivalenca.turnover.spike. Watch with:
//   log stream --style compact --level debug --predicate 'subsystem == "com.guivalenca.turnover.spike"'

import AppKit
import ApplicationServices
import FinderSync
import IOKit.hid
import os

let spikeLog = Logger(subsystem: "com.guivalenca.turnover.spike", category: "app")

func say(_ message: String) {
    spikeLog.notice("\(message, privacy: .public)")
}

@main
@MainActor
enum Main {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)  // same as LSUIElement: no Dock icon
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let ring = RingPanelController()
    private lazy var watcher = DragWatcher(ring: ring)

    func applicationDidFinishLaunching(_ notification: Notification) {
        say("launched pid=\(getpid()) path=\(Bundle.main.bundlePath)")
        if UserDefaults.standard.object(forKey: "logPermissions") as? Bool ?? true { logStatus() }
        watcher.start()
    }

    /// Permission and registration state. The spike must run with all of these denied.
    private func logStatus() {
        let listen: String
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted: listen = "granted"
        case kIOHIDAccessTypeDenied: listen = "denied"
        default: listen = "unknown"
        }
        say("permissions: AXIsProcessTrusted=\(AXIsProcessTrusted()) "
            + "CGPreflightListenEventAccess(InputMonitoring)=\(CGPreflightListenEventAccess()) "
            + "IOHIDCheckAccess(ListenEvent)=\(listen) "
            + "CGPreflightPostEventAccess=\(CGPreflightPostEventAccess())")
        say("FIFinderSyncController.isExtensionEnabled=\(FIFinderSyncController.isExtensionEnabled)")
    }

    // MARK: - Transport from the Finder Sync extension

    // The sandboxed extension opens turnover-spike://convert?to=png&file=/a&file=/b
    // with NSWorkspace (activates = false). LaunchServices delivers it here, launching the app if needed.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { handle(url) }
    }

    private func handle(_ url: URL) {
        guard url.scheme == "turnover-spike",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            say("ignored URL \(url.absoluteString)")
            return
        }
        let items = components.queryItems ?? []
        switch components.host {
        case "convert":
            let target = items.first { $0.name == "to" }?.value ?? "?"
            let files = items.filter { $0.name == "file" }.compactMap(\.value).map { URL(fileURLWithPath: $0) }
            let exist = files.map { FileManager.default.fileExists(atPath: $0.path) }
            say("TRANSPORT received convert to=\(target) files=\(files.map(\.path)) exist=\(exist) "
                + "urlLength=\(url.absoluteString.count) frontmost=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "nil")")
        case "status":
            logStatus()
        case "manage-extensions":
            say("calling FIFinderSyncController.showExtensionManagementInterface()")
            FIFinderSyncController.showExtensionManagementInterface()
        case "quit":
            say("quit requested")
            NSApp.terminate(nil)
        default:
            say("unknown command \(url.absoluteString)")
        }
    }
}
