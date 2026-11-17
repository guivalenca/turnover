import AppKit
import SwiftUI
import TurnoverKit

/// The menu bar item, present only while `Feedback` says so: the glyph and the overall
/// percentage, with a menu listing each running conversion with a ✕.
@MainActor
final class StatusItem: NSObject, NSMenuDelegate {
    private let feedback: Feedback
    private var item: NSStatusItem?
    private let menu = NSMenu()
    private var isMenuOpen = false

    init(feedback: Feedback) {
        self.feedback = feedback
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        follow()
    }

    /// Updates the item now and again whenever what it shows changes.
    private func follow() {
        withObservationTracking(update) {
            Task { @MainActor [weak self] in self?.follow() }
        }
    }

    private func update() {
        // An open menu stays until it closes, even if the item's time is up.
        guard feedback.showsStatusItem || isMenuOpen else {
            if let item {
                NSStatusBar.system.removeStatusItem(item)
                log.info("Removed the menu bar item")
            }
            item = nil
            menu.removeAllItems()  // let go of the jobs
            return
        }
        let item = item ?? makeItem()
        let title = percent(feedback.progress)
        if item.button?.title != title { item.button?.title = title }
    }

    private func makeItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(named: "MenuBarGlyph")  // already a template (#14)
        item.button?.imagePosition = .imageLeading
        item.button?.setAccessibilityLabel("Turnover")
        item.button?.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        item.menu = menu
        self.item = item
        log.info("Showing the menu bar item")
        return item
    }

    /// Fills the menu as it opens: a row per unfinished job, running ones first. The rows stay
    /// put while it is open, each showing its job live ("Stopped", "Done"), so stopping one never
    /// slides the next ✕ under the pointer, and a job that starts meanwhile shows on the next open.
    private func rebuildMenu() {
        menu.removeAllItems()
        let jobs = feedback.runningJobs + feedback.waitingJobs
        for job in jobs.prefix(Self.mostRows) {
            let row = NSMenuItem()
            let view = NSHostingView(rootView: JobRow(job: job))
            view.frame.size = view.fittingSize
            row.view = view
            menu.addItem(row)
        }
        if jobs.count > Self.mostRows {
            menu.addItem(Self.note("\(jobs.count - Self.mostRows) more waiting"))
        }
        if jobs.isEmpty {
            menu.addItem(Self.note("Done"))
        }
        if jobs.count > 1 {
            menu.addItem(.separator())
            let stopAll = NSMenuItem(title: "Stop All", action: #selector(stopAll), keyEquivalent: "")
            stopAll.target = self
            menu.addItem(stopAll)
        }
    }

    private static let mostRows = 8

    private static func note(_ text: String) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func stopAll() {
        feedback.cancelAll()
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
    }

    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
        update()
    }
}
