import AppKit

/// A full-screen, transparent, non-activating panel that becomes the drag destination
/// everywhere on screen while it is visible. One drop target sits 95 pt above the ring centre.
///
/// Tunables (read on every open), e.g. `defaults write com.guivalenca.turnover.spike fillAlpha -float 0`:
/// - fillAlpha (default 0.02): alpha of the full-screen fill. Tests whether a fully clear panel still catches drops.
/// - shrinkInside (default 28), shrinkOutside (default 56): drag-image size in points inside/outside the ring.
/// - glass (default true): put an NSGlassEffectView disc behind the target (macOS 26+).
@MainActor
final class RingPanelController {
    var onDragFinished: ((String) -> Void)?
    private(set) var isOpen = false
    private(set) var isClosing = false
    private var generation = 0
    private var panel: NSPanel?
    private var dropView: DropView?

    func open(at screenPoint: NSPoint) {
        let screen = NSScreen.screens.first { NSMouseInRect(screenPoint, $0.frame, false) } ?? NSScreen.main!
        let panel = self.panel ?? makePanel()
        let view = dropView!
        panel.setFrame(screen.frame, display: false)
        let defaults = UserDefaults.standard
        view.fillAlpha = CGFloat(defaults.object(forKey: "fillAlpha") as? Double ?? 0.02)
        view.shrinkInside = CGFloat(defaults.object(forKey: "shrinkInside") as? Double ?? 28)
        view.shrinkOutside = CGFloat(defaults.object(forKey: "shrinkOutside") as? Double ?? 56)
        view.useGlass = defaults.object(forKey: "glass") as? Bool ?? true
        view.reset(center: NSPoint(x: screenPoint.x - screen.frame.minX, y: screenPoint.y - screen.frame.minY))
        panel.orderFrontRegardless()
        isOpen = true
        // Safety net: a full-screen panel left open would swallow every click. Never let it outlive 20 s.
        generation += 1
        let opened = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            guard let self, self.isOpen, self.generation == opened else { return }
            self.close(reason: "watchdog (20 s)")
        }
        // Only the access policy is logged; the pasteboard is not read here (no privacy prompt risk).
        if #available(macOS 15.4, *) {
            say("drag pasteboard accessBehavior=\(NSPasteboard(name: .drag).accessBehavior.rawValue) "
                + "general accessBehavior=\(NSPasteboard.general.accessBehavior.rawValue) (0 default, 1 ask, 2 alwaysAllow, 3 alwaysDeny)")
        }
        say("ring panel ordered front: screen=\(screen.frame) center=\(screenPoint) level=\(panel.level.rawValue) "
            + "fillAlpha=\(view.fillAlpha) glass=\(view.useGlass) appActive=\(NSApp.isActive)")
    }

    func close(reason: String) {
        guard isOpen, let panel else { return }
        isClosing = true
        panel.orderOut(nil)
        isClosing = false
        isOpen = false
        say("ring panel closed: \(reason)")
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSScreen.main!.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = false
        panel.becomesKeyOnlyIfNeeded = true
        let view = DropView(frame: NSRect(origin: .zero, size: panel.frame.size))
        view.autoresizingMask = [.width, .height]
        view.controller = self
        panel.contentView = view
        self.panel = panel
        self.dropView = view
        return panel
    }
}

/// The panel's content view and the drag destination.
@MainActor
final class DropView: NSView {
    weak var controller: RingPanelController?
    var fillAlpha: CGFloat = 0.02
    var shrinkInside: CGFloat = 28
    var shrinkOutside: CGFloat = 56
    var useGlass = true

    private let ringRadius: CGFloat = 140
    private let targetOffset: CGFloat = 95
    private let targetRadius: CGFloat = 42
    private var ringCenter: NSPoint = .zero
    private var currentImageSize: CGFloat?
    private var updates = 0
    private var fileCount = 0
    private let overlay = RingOverlay()
    private var glass: NSView?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
        overlay.autoresizingMask = [.width, .height]
        overlay.frame = bounds
        addSubview(overlay)
    }

    required init?(coder: NSCoder) { fatalError() }

    private var targetCenter: NSPoint { NSPoint(x: ringCenter.x, y: ringCenter.y + targetOffset) }

    private func isOnTarget(_ p: NSPoint) -> Bool {
        hypot(p.x - targetCenter.x, p.y - targetCenter.y) <= targetRadius
    }

    private func isInsideRing(_ p: NSPoint) -> Bool {
        hypot(p.x - ringCenter.x, p.y - ringCenter.y) <= ringRadius
    }

    func reset(center: NSPoint) {
        ringCenter = center
        currentImageSize = nil
        updates = 0
        fileCount = 0
        glass?.removeFromSuperview()
        glass = nil
        if useGlass {
            let disc = NSRect(x: center.x - ringRadius, y: center.y - ringRadius, width: ringRadius * 2, height: ringRadius * 2)
            let view: NSView
            if #available(macOS 26.0, *) {
                let g = PassthroughGlass(frame: disc)
                g.cornerRadius = ringRadius
                g.style = .regular
                view = g
            } else {
                let v = PassthroughVisualEffect(frame: disc)
                v.material = .hudWindow
                v.blendingMode = .behindWindow
                v.state = .active
                v.wantsLayer = true
                v.layer?.cornerRadius = ringRadius
                v.layer?.masksToBounds = true
                view = v
            }
            addSubview(view, positioned: .below, relativeTo: overlay)
            glass = view
        }
        overlay.update(center: center, ringRadius: ringRadius, target: targetCenter, targetRadius: targetRadius,
                       highlighted: false, hub: "⇧ ring")
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(fillAlpha).setFill()
        dirtyRect.fill()
    }

    // MARK: - NSDraggingDestination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let urls = fileURLs(sender)
        fileCount = urls.count
        say("draggingEntered seq=\(sender.draggingSequenceNumber) sourceMask=\(sender.draggingSourceOperationMask.rawValue) "
            + "validItems=\(sender.numberOfValidItemsForDrop) formation=\(sender.draggingFormation.rawValue) "
            + "types=\(sender.draggingPasteboard.types?.map(\.rawValue) ?? []) urls=\(urls.map(\.path))")
        logOriginalImage(sender)
        return update(sender, reason: "entered")
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        updates += 1
        if updates == 1 { say("first draggingUpdated") }
        return update(sender, reason: "updated")
    }

    override func updateDraggingItemsForDrag(_ sender: NSDraggingInfo?) {
        say("updateDraggingItemsForDrag called (sender nil=\(sender == nil))")
    }

    override func wantsPeriodicDraggingUpdates() -> Bool { true }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        let closing = controller?.isClosing ?? false
        say("draggingExited closingByUs=\(closing) leftDown=\(NSEvent.pressedMouseButtons & 1 != 0) updates=\(updates)")
        if !closing { controller?.onDragFinished?("draggingExited") }
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let ok = isOnTarget(convert(sender.draggingLocation, from: nil))
        say("prepareForDragOperation onTarget=\(ok)")
        return ok
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = fileURLs(sender)
        say("DROP ACCEPTED performDragOperation urls=\(urls.map(\.path))")
        return true
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        say("concludeDragOperation")
        controller?.onDragFinished?("concluded")
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        say("draggingEnded")
        controller?.onDragFinished?("draggingEnded")
    }

    // MARK: - Helpers

    private func update(_ sender: NSDraggingInfo, reason: String) -> NSDragOperation {
        let point = convert(sender.draggingLocation, from: nil)
        let onTarget = isOnTarget(point)
        overlay.update(center: ringCenter, ringRadius: ringRadius, target: targetCenter, targetRadius: targetRadius,
                       highlighted: onTarget, hub: onTarget ? "PNG · \(fileCount) file\(fileCount == 1 ? "" : "s")" : "⇧ ring")
        shrinkImages(sender, to: isInsideRing(point) ? shrinkInside : shrinkOutside, reason: reason)
        guard onTarget else { return [] }
        let mask = sender.draggingSourceOperationMask
        return mask.contains(.copy) ? .copy : (mask.contains(.generic) ? .generic : [])
    }

    /// Replace the source's drag images (Finder: icon + name label) with small icons around the cursor.
    private func shrinkImages(_ sender: NSDraggingInfo, to size: CGFloat, reason: String) {
        guard currentImageSize != size else { return }
        currentImageSize = size
        sender.animatesToDestination = false
        sender.draggingFormation = .stack
        let cursor = convert(sender.draggingLocation, from: nil)
        var count = 0
        sender.enumerateDraggingItems(
            options: [.clearNonenumeratedImages],
            for: self,
            classes: [NSURL.self],
            searchOptions: [.urlReadingFileURLsOnly: true]
        ) { item, index, _ in
            guard let url = item.item as? URL else { return }
            // Prefer Finder's own icon image (a real thumbnail) from the source's "icon" component;
            // fall back to the generic type icon from NSWorkspace.
            let sourceIcon = item.imageComponents?.first { $0.key == .icon }?.contents
            let icon: Any = sourceIcon ?? NSWorkspace.shared.icon(forFile: url.path)
            if index == 0 { say("drag image source: \(sourceIcon == nil ? "NSWorkspace icon" : "Finder's icon component (\(type(of: sourceIcon!)))")") }
            let offset = CGFloat(min(index, 4)) * 3
            let frame = NSRect(x: cursor.x - size / 2 + offset, y: cursor.y - size / 2 - offset, width: size, height: size)
            item.setDraggingFrame(frame, contents: icon)
            count += 1
        }
        say("drag image set to \(Int(size))pt for \(count) item(s) (\(reason))")
    }

    private func logOriginalImage(_ sender: NSDraggingInfo) {
        var descriptions: [String] = []
        sender.enumerateDraggingItems(options: [], for: self, classes: [NSURL.self],
                                      searchOptions: [.urlReadingFileURLsOnly: true]) { item, index, _ in
            if index < 3 {
                let components = item.imageComponents?.map { "\($0.key.rawValue):\($0.frame)" } ?? []
                descriptions.append("#\(index) frame=\(item.draggingFrame) components=\(components)")
            }
        }
        say("source drag images: \(descriptions)")
    }

    private func fileURLs(_ sender: NSDraggingInfo) -> [URL] {
        sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                              options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }
}

/// Draws the ring outline, the single drop target and the hub text. Never intercepts the drag.
final class RingOverlay: NSView {
    private var center: NSPoint = .zero
    private var ringRadius: CGFloat = 0
    private var target: NSPoint = .zero
    private var targetRadius: CGFloat = 0
    private var highlighted = false
    private var hub = ""

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(center: NSPoint, ringRadius: CGFloat, target: NSPoint, targetRadius: CGFloat, highlighted: Bool, hub: String) {
        guard center != self.center || highlighted != self.highlighted || hub != self.hub else { return }
        self.center = center
        self.ringRadius = ringRadius
        self.target = target
        self.targetRadius = targetRadius
        self.highlighted = highlighted
        self.hub = hub
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let ring = NSBezierPath(ovalIn: NSRect(x: center.x - ringRadius, y: center.y - ringRadius,
                                               width: ringRadius * 2, height: ringRadius * 2))
        ring.lineWidth = 2
        NSColor.labelColor.withAlphaComponent(0.35).setStroke()
        ring.stroke()

        let t = NSBezierPath(ovalIn: NSRect(x: target.x - targetRadius, y: target.y - targetRadius,
                                            width: targetRadius * 2, height: targetRadius * 2))
        (highlighted ? NSColor.controlAccentColor.withAlphaComponent(0.6) : NSColor.labelColor.withAlphaComponent(0.12)).setFill()
        t.fill()
        drawText("PNG", at: target, size: 17, weight: .semibold)
        drawText(hub, at: center, size: 13, weight: .medium)
    }

    private func drawText(_ text: String, at point: NSPoint, size: CGFloat, weight: NSFont.Weight) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: NSColor.labelColor,
        ]
        let s = NSAttributedString(string: text, attributes: attributes)
        let bounds = s.size()
        s.draw(at: NSPoint(x: point.x - bounds.width / 2, y: point.y - bounds.height / 2))
    }
}

@available(macOS 26.0, *)
final class PassthroughGlass: NSGlassEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class PassthroughVisualEffect: NSVisualEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
