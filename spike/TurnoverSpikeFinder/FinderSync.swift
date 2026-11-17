// Finder Sync extension for the spike. Sandboxed (app extensions must be), signed ad hoc.
// It never writes files: it builds the "Turnover ›" submenu and forwards the choice to the app
// by opening turnover-spike://convert?to=<target>&file=<path>... with NSWorkspace.

import Cocoa
import FinderSync
import os
import UniformTypeIdentifiers

private let log = Logger(subsystem: "com.guivalenca.turnover.spike", category: "finder")

private func say(_ message: String) {
    log.notice("\(message, privacy: .public)")
}

final class FinderSync: FIFinderSync {
    override init() {
        super.init()
        say("extension init pid=\(getpid()) main=\(Thread.isMainThread) bundle=\(Bundle.main.bundlePath)")
        Self.observeAllVolumes()
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didMountNotification, object: nil, queue: .main
        ) { _ in
            Self.observeAllVolumes()
        }
    }

    /// "/" covers the boot volume; other volumes must be added explicitly.
    private static func observeAllVolumes() {
        var directories: Set<URL> = [URL(fileURLWithPath: "/")]
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil,
                                                            options: [.skipHiddenVolumes]) ?? []
        directories.formUnion(volumes)
        FIFinderSyncController.default().directoryURLs = directories
        say("observing \(directories.map(\.path).sorted())")
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let controller = FIFinderSyncController.default()
        let selected = controller.selectedItemURLs() ?? []
        say("menu(for: \(menuKind.rawValue)) main=\(Thread.isMainThread) selected=\(selected.map(\.path)) "
            + "targeted=\(controller.targetedURL()?.path ?? "nil")")
        guard menuKind == .contextualMenuForItems else { return nil }

        var images = 0
        var videos = 0
        for url in selected {
            // Can the sandboxed extension read the content type, or only guess from the extension?
            let resourceType: UTType?
            do {
                resourceType = try url.resourceValues(forKeys: [.contentTypeKey]).contentType
            } catch {
                say("  contentTypeKey failed for \(url.lastPathComponent): \(error)")
                resourceType = nil
            }
            let extensionType = UTType(filenameExtension: url.pathExtension)
            say("  \(url.lastPathComponent): contentTypeKey=\(resourceType?.identifier ?? "nil") "
                + "byExtension=\(extensionType?.identifier ?? "nil")")
            let type = resourceType ?? extensionType
            if type?.conforms(to: .image) == true { images += 1 }
            else if type?.conforms(to: .movie) == true { videos += 1 }
        }
        guard images + videos > 0 else {
            say("nothing convertible: no Turnover menu")
            return NSMenu(title: "")
        }

        let submenu = NSMenu(title: "Turnover")
        if images > 0 {
            submenu.addItem(item("PNG", count: images, noun: "image", action: #selector(convertToPNG(_:)), tag: 1))
            submenu.addItem(item("JPEG", count: images, noun: "image", action: #selector(convertToJPEG(_:)), tag: 2))
        }
        if videos > 0 {
            submenu.addItem(item("MP4", count: videos, noun: "video", action: #selector(convertToMP4(_:)), tag: 3))
        }
        let top = NSMenuItem(title: "Turnover", action: nil, keyEquivalent: "")
        top.submenu = submenu
        let menu = NSMenu(title: "")
        menu.addItem(top)
        return menu
    }

    private func item(_ title: String, count: Int, noun: String, action: Selector, tag: Int) -> NSMenuItem {
        let item = NSMenuItem(title: "\(title) (\(count) \(noun)\(count == 1 ? "" : "s"))", action: action, keyEquivalent: "")
        item.tag = tag
        item.representedObject = "rep-\(title)"  // logged on click to see whether Finder preserves it
        return item
    }

    // NOT @IBAction: in Swift 6 @IBAction implies @MainActor, but Finder delivers menu commands on an
    // XPC queue (FIFinderSyncExtension executeCommandWithMenuItemDictionary:), so the runtime isolation
    // check traps (EXC_BREAKPOINT in dispatch_assert_queue). Plain @objc methods are nonisolated.
    @objc func convertToPNG(_ sender: AnyObject?) { forward("png", sender) }
    @objc func convertToJPEG(_ sender: AnyObject?) { forward("jpeg", sender) }
    @objc func convertToMP4(_ sender: AnyObject?) { forward("mp4", sender) }

    private func forward(_ target: String, _ sender: AnyObject?) {
        let menuItem = sender as? NSMenuItem
        let selected = FIFinderSyncController.default().selectedItemURLs() ?? []
        say("action \(target) main=\(Thread.isMainThread) senderTitle=\(menuItem?.title ?? "nil") tag=\(menuItem?.tag ?? -1) "
            + "representedObject=\(String(describing: menuItem?.representedObject)) selected=\(selected.map(\.path))")

        var components = URLComponents()
        components.scheme = "turnover-spike"
        components.host = "convert"
        components.queryItems = [URLQueryItem(name: "to", value: target)]
            + selected.map { URLQueryItem(name: "file", value: $0.path) }
        guard let url = components.url else { return }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.open(url, configuration: configuration) { app, error in
            say("NSWorkspace.open -> app=\(app?.bundleIdentifier ?? "nil") error=\(String(describing: error))")
        }
    }
}
