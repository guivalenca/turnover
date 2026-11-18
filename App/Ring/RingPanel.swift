import AppKit
import RingModel

/// What the ring's panels tell the ring about the drag they catch.
@MainActor
protocol RingPanelDelegate: AnyObject {
    /// The drag reached the panels: its files, from the drag itself.
    func ringPanel(_ panel: RingPanel, draggingFiles files: [URL])
    /// The pointer is at `point` (screen coordinates). Returns whether a drop there converts.
    func ringPanel(_ panel: RingPanel, pointerAt point: NSPoint) -> Bool
    /// The files were dropped on an entry. Returns whether they are converted.
    func ringPanelDrop(_ panel: RingPanel) -> Bool
    /// The drag left without a drop on an entry: Esc if the button is still down, otherwise a
    /// drop somewhere else.
    func ringPanel(_ panel: RingPanel, dragLeftWithButtonDown buttonDown: Bool)
}

/// While the ring is open: a transparent, non-activating panel over every screen that is the
/// drop destination everywhere, so a drop anywhere off the ring's entries is refused and the drag
/// slides back. The ring itself is drawn above them in its own window (`RingWindow`), which the
/// drag goes through, on the screen it opened on and kept fully on it.
///
/// The spike's (#2) findings, kept here:
/// - A fully clear panel still catches drags over every pixel; no fill is needed.
/// - The drag session only notices the panel on the pointer's first movement after it appears,
///   so the files and the first pointer position arrive then.
/// - Closing it ourselves sends `draggingExited`, which must be ignored.
@MainActor
final class RingPanel {
    weak var delegate: RingPanelDelegate?

    private(set) var isOpen = false
    /// The ring's centre, in screen coordinates: where the pointer was, unless that is too near an
    /// edge for the whole ring to show.
    private(set) var centre: NSPoint = .zero
    /// True while `close()` orders the panels out, so their `draggingExited` is ignored.
    fileprivate var isClosing = false

    private var panels: [NSPanel] = []
    private let ring = RingWindow()
    private var watchdog: Timer?
    /// The pointer's angle around the centre (the model's degrees), for the highlight's turn.
    private var pointerAngle: Double?
    /// How many more of the drag's updates make the drag image small, for this opening.
    fileprivate var dragImageShrinks = 0
    /// The pasteboard types an image dragged as a picture carries; empty for a drag of files.
    /// The panels take the drag whatever it carries, and its drag image is the picture's.
    fileprivate var pictureTypes: [NSPasteboard.PasteboardType] = []
    /// A small picture of the dragged image, once there is one: the drag image over the ring.
    var pictureThumbnail: NSImage? {
        // Shrunk again at the next update, with the picture.
        didSet { dragImageShrinks = Self.pictureShrinks }
    }

    /// Keeps this far from a screen's edges, menu bar and Dock.
    private static let edgeMargin: CGFloat = 8
    /// The drag image's size over the ring: about the prototype's (a thumbnail at 45%).
    static let dragImageSide: CGFloat = 32
    /// How many updates in a row make a dragged picture's image small. Done once, as for files,
    /// the browser's large image stayed over the ring until the pointer moved again (seen with
    /// real drags from Chrome); done on the next few updates, it is small at once.
    fileprivate static let pictureShrinks = 4

    /// Shows the panels, with the ring centred on `point` (screen coordinates), or as near it as
    /// keeps the ring on screen. `pictureTypes`: what the drag pasteboard holds, for an image
    /// dragged as a picture rather than as a file, so that the panels are its destination too.
    func open(at point: NSPoint, pictureTypes: [NSPasteboard.PasteboardType] = []) {
        self.pictureTypes = pictureTypes
        let screens = NSScreen.screens
        let screen = screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
        // The visible frame leaves out the menu bar (and a notch) and the Dock.
        let area = (screen?.visibleFrame ?? NSRect(origin: point, size: .zero)).insetBy(dx: Self.edgeMargin, dy: Self.edgeMargin)
        centre = RingGeometry.centre(openingAt: point, drawing: RingView.drawing, within: area)
        while panels.count < screens.count { panels.append(makePanel()) }
        for (panel, screen) in zip(panels, screens) {
            panel.setFrame(screen.frame, display: false)
            panel.contentView?.unregisterDraggedTypes()
            panel.contentView?.registerForDraggedTypes([.fileURL] + pictureTypes)
            panel.orderFrontRegardless()
        }
        ring.show(at: centre)
        pointerAngle = nil
        dragImageShrinks = pictureTypes.isEmpty ? 1 : Self.pictureShrinks
        isOpen = true
        startWatchdog()
    }

    /// Redraws the ring for the model's current state.
    func show(_ model: RingModel) {
        ring.ringView.pointerAngle = pointerAngle
        ring.ringView.look = RingLook(model)
    }

    /// The drag is at `point` (screen coordinates).
    fileprivate func pointerMoved(to point: NSPoint) {
        // The model's angles grow clockwise on screen, where AppKit's y grows upwards.
        pointerAngle = atan2(centre.y - point.y, point.x - centre.x) * 180 / .pi
    }

    func close() {
        guard isOpen else { return }
        isClosing = true
        for panel in panels { panel.orderOut(nil) }
        isClosing = false
        isOpen = false
        ring.hide()
        watchdog?.invalidate()
        watchdog = nil
    }

    /// A full-screen panel left open would swallow every click. The ring closes when the drag
    /// ends, but if that is ever missed, this closes it once the button has been up a moment.
    private func startWatchdog() {
        watchdog?.invalidate()
        var upSince: Date?
        watchdog = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isOpen else { return }
                guard NSEvent.pressedMouseButtons & 1 == 0 else { upSince = nil; return }
                if let since = upSince, Date.now.timeIntervalSince(since) > 1.5 {
                    ringLog.error("Ring left open after the drag; closing it")
                    self.delegate?.ringPanel(self, dragLeftWithButtonDown: false)
                    self.close()
                } else if upSince == nil {
                    upSince = .now
                }
            }
        }
    }

    private func makePanel() -> NSPanel {
        // Catching the drag everywhere, transparent or not (see `overlay`).
        let panel = NSPanel.overlay(ignoresMouse: false)
        panel.becomesKeyOnlyIfNeeded = true
        let catcher = DropView()
        catcher.ring = self
        panel.contentView = catcher
        return panel
    }
}

/// A panel's content view: the drag destination.
@MainActor
private final class DropView: NSView {
    weak var ring: RingPanel?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        ringLog.debug("draggingEntered: pointer \(NSStringFromPoint(NSEvent.mouseLocation), privacy: .public), seq \(sender.draggingSequenceNumber)")
        if let ring, let files = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !files.isEmpty {
            ring.delegate?.ringPanel(ring, draggingFiles: files)
        }
        return update(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        update(sender)
    }

    /// Keeps `draggingUpdated` coming while the pointer is still, so the operation follows the
    /// ring when estimates arrive.
    override func wantsPeriodicDraggingUpdates() -> Bool { true }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        !update(sender).isEmpty
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let ring else { return false }
        return ring.delegate?.ringPanelDrop(ring) ?? false
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        guard let ring, !ring.isClosing, ring.isOpen, let window else { return }
        let buttonDown = NSEvent.pressedMouseButtons & 1 != 0
        ringLog.debug("draggingExited: button \(buttonDown ? "down" : "up", privacy: .public), pointer \(NSStringFromPoint(NSEvent.mouseLocation), privacy: .public), panel \(NSStringFromRect(window.frame), privacy: .public)")
        // Onto another screen's panel: the drag goes on there.
        if buttonDown, !window.frame.contains(NSEvent.mouseLocation) { return }
        ring.delegate?.ringPanel(ring, dragLeftWithButtonDown: buttonDown)
    }

    /// A drop on an entry is a copy for the source (Finder leaves the file alone); anywhere else
    /// it is refused, and the drag slides back.
    private func update(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let ring, let window else { return [] }
        let point = window.convertPoint(toScreen: sender.draggingLocation)
        ring.pointerMoved(to: point)
        if ring.dragImageShrinks > 0 {
            ring.dragImageShrinks -= 1
            shrinkDragImage(sender)
        }
        guard ring.delegate?.ringPanel(ring, pointerAt: point) == true else { return [] }
        return sender.draggingSourceOperationMask.contains(.copy) ? .copy : .generic
    }

    /// Makes the drag image small while the ring is open, so it hides less of the ring: the
    /// dragged files' own icons, without their names, shrunk around the pointer (the spike's
    /// approach, #2). The source's image comes back by itself when the panels close.
    private func shrinkDragImage(_ sender: NSDraggingInfo) {
        sender.animatesToDestination = false
        sender.draggingFormation = .stack
        let pointer = convert(sender.draggingLocation, from: nil)
        if let ring, !ring.pictureTypes.isEmpty {
            // An image dragged as a picture: the browser's drag image is the picture itself,
            // often large. Our own small picture of it replaces it, once it has been decoded.
            sender.enumerateDraggingItems(options: [], for: self, classes: [NSPasteboardItem.self], searchOptions: [:]) { item, _, _ in
                guard let contents = ring.pictureThumbnail ?? item.imageComponents?.first?.contents else { return }
                let frame = RingGeometry.shrink(item.draggingFrame, toward: pointer, side: Self.dragImageSide)
                item.setDraggingFrame(frame, contents: contents)
            }
            return
        }
        sender.enumerateDraggingItems(options: [.clearNonenumeratedImages], for: self, classes: [NSURL.self],
                                      searchOptions: [.urlReadingFileURLsOnly: true]) { item, index, _ in
            let components = item.imageComponents ?? []
            let frame: NSRect, contents: Any?
            // Finder's icon component is the real thumbnail, readable from another process.
            if let icon = components.first(where: { $0.key == .icon }) ?? components.first {
                let iconFrame = icon.frame.offsetBy(dx: item.draggingFrame.minX, dy: item.draggingFrame.minY)
                frame = RingGeometry.shrink(iconFrame, toward: pointer, side: Self.dragImageSide)
                contents = icon.contents
            } else if let url = item.item as? URL {
                let side = Self.dragImageSide
                frame = NSRect(x: pointer.x - side / 2, y: pointer.y - side / 2, width: side, height: side)
                contents = NSWorkspace.shared.icon(forFile: url.path)
            } else {
                return
            }
            // A small stack for several files.
            let offset = CGFloat(min(index, 3)) * 3
            item.setDraggingFrame(frame.offsetBy(dx: offset, dy: -offset), contents: contents)
        }
    }

    /// The drag image's size over the ring: about the prototype's (a thumbnail at 45%).
    private static var dragImageSide: CGFloat { RingPanel.dragImageSide }
}
