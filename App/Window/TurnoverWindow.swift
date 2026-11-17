import AppKit
import SwiftUI

/// The app's one window. Closing it keeps the app running, windowless, until it's shown again.
@MainActor
final class TurnoverWindow: NSObject, NSWindowDelegate {
    private let model = WindowModel()

    private lazy var window: NSWindow = {
        let window = NSWindow(contentViewController: NSHostingController(rootView: TurnoverView(model: model)))
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.title = String(localized: "Turnover")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        // Shown on whichever Space the user is on, rather than switching back to the one it
        // was first opened on.
        window.collectionBehavior = [.moveToActiveSpace]
        window.isRestorable = false
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }()

    /// Brings the window forward, opening it if needed.
    func show() {
        model.startWatching()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        // In front even when the system doesn't let the app activate (launched from a shell
        // that isn't frontmost, say). A click then activates it.
        window.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        model.stopWatching()
    }
}

/// An agent app has no menu bar of its own, but its key equivalents still work while it's
/// active: ⌘W closes the window and ⌘Q quits.
enum MainMenu {
    @MainActor static func install() {
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: String(localized: "Quit Turnover"), action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        let fileMenu = NSMenu(title: String(localized: "File"))
        fileMenu.addItem(
            withTitle: String(localized: "Close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let menu = NSMenu()
        for submenu in [appMenu, fileMenu] {
            let item = NSMenuItem()
            item.submenu = submenu
            menu.addItem(item)
        }
        NSApp.mainMenu = menu
    }
}
