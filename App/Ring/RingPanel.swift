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
/// slides back. The ring itself is drawn on the screen it opened on.
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
    /// The ring's centre, in screen coordinates.
    private(set) var centre: NSPoint = .zero
    /// True while `close()` orders the panels out, so their `draggingExited` is ignored.
    fileprivate var isClosing = false

    private var panels: [NSPanel] = []
    private var ringView: RingView?
    private var watchdog: Timer?

    /// Shows the panels, with the ring centred on `point` (screen coordinates).
    func open(at point: NSPoint) {
        centre = point
        let screens = NSScreen.screens
        while panels.count < screens.count { panels.append(makePanel()) }
        for (panel, screen) in zip(panels, screens) {
            panel.setFrame(screen.frame, display: false)
            let catcher = panel.contentView as! DropView
            if NSMouseInRect(point, screen.frame, false) {
                let view = ringView ?? RingView()
                view.frame = catcher.bounds
                view.centre = NSPoint(x: point.x - screen.frame.minX, y: screen.frame.maxY - point.y)
                catcher.addSubview(view)
                ringView = view
            }
            panel.orderFrontRegardless()
        }
        isOpen = true
        startWatchdog()
    }

    /// Redraws the ring for the model's current state.
    func show(_ model: RingModel) {
        ringView?.model = model
    }

    func close() {
        guard isOpen else { return }
        isClosing = true
        for panel in panels { panel.orderOut(nil) }
        ringView?.removeFromSuperview()
        isClosing = false
        isOpen = false
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
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
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
        // Onto another screen's panel: the drag goes on there.
        if buttonDown, !window.frame.contains(NSEvent.mouseLocation) { return }
        ring.delegate?.ringPanel(ring, dragLeftWithButtonDown: buttonDown)
    }

    /// A drop on an entry is a copy for the source (Finder leaves the file alone); anywhere else
    /// it is refused, and the drag slides back.
    private func update(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let ring, let window else { return [] }
        let point = window.convertPoint(toScreen: sender.draggingLocation)
        guard ring.delegate?.ringPanel(ring, pointerAt: point) == true else { return [] }
        return sender.draggingSourceOperationMask.contains(.copy) ? .copy : .generic
    }
}
