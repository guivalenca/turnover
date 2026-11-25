import AppKit
import FinderSync
import os
import TurnoverKit

private let log = Logger(subsystem: "com.guivalenca.turnover", category: "finder")

/// The Finder Sync extension. It adds a top-level "Turnover ›" submenu to Finder's right-click
/// menu, with one item per format that fits the selection ("PNG (3 images)"), and hands the
/// choice to the app as a `turnover://convert` URL. It never converts or writes anything.
///
/// Finder calls `menu(for:)` and the menu actions off the main thread, and may run several
/// instances of the extension at once, so nothing here is main-actor or keeps state.
final class FinderSync: FIFinderSync {
    override init() {
        super.init()
        Self.observeAllVolumes()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { _ in Self.observeAllVolumes() }
        }
    }

    /// Asks Finder for menus everywhere: "/" covers the startup disk, and every other volume
    /// (external drives, disk images, shares) has to be listed too.
    private static func observeAllVolumes() {
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: []) ?? []
        FIFinderSyncController.default().directoryURLs = Set(volumes).union([URL(fileURLWithPath: "/")])
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems else { return nil }
        let menu = NSMenu(title: "")
        let offers = Offers(declaredTypesOf: FIFinderSyncController.default().selectedItemURLs() ?? [])
        guard !offers.targets.isEmpty else { return menu }  // empty: Finder shows no Turnover item

        let submenu = NSMenu(title: "Turnover")
        for (index, group) in offers.groups.enumerated() {
            if index > 0 { submenu.addItem(.separator()) }
            for target in group.targets {
                submenu.addItem(NSMenuItem(title: target.menuTitle, action: Self.action(for: target.format), keyEquivalent: ""))
            }
        }
        let item = NSMenuItem(title: "Turnover", action: nil, keyEquivalent: "")
        item.submenu = submenu
        menu.addItem(item)
        return menu
    }

    // One action per format: a clicked item's `representedObject` doesn't survive the trip back
    // from Finder. Plain @objc, never @IBAction: Swift 6 makes an @IBAction main-actor, and
    // Finder calls it on another queue, which traps.
    @objc func convertToPNG(_ sender: AnyObject?) { convert(to: .png) }
    @objc func convertToJPEG(_ sender: AnyObject?) { convert(to: .jpeg) }
    @objc func convertToMP4(_ sender: AnyObject?) { convert(to: .mp4) }
    @objc func makeSmaller(_ sender: AnyObject?) { convert(to: .smaller) }

    private static func action(for format: OutputFormat) -> Selector? {
        switch format {
        case .png: #selector(convertToPNG(_:))
        case .jpeg: #selector(convertToJPEG(_:))
        case .mp4: #selector(convertToMP4(_:))
        case .smaller: #selector(makeSmaller(_:))
        case .original: nil  // never offered for files on disk
        }
    }

    /// Sends the files the chosen format applies to, in a mixed selection only those, to the app.
    /// Finder stays in front, and the app is launched if it isn't running.
    private func convert(to format: OutputFormat) {
        let selection = FIFinderSyncController.default().selectedItemURLs() ?? []
        guard let target = Offers(declaredTypesOf: selection).targets.first(where: { $0.format == format }) else {
            log.error("Nothing in the selection converts to \(format.name, privacy: .public)")
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.open(ConversionRequest(format: format, files: target.files).url,
                                configuration: configuration) { _, error in
            if let error { log.error("Couldn't reach the app: \(error.localizedDescription, privacy: .public)") }
        }
    }
}
