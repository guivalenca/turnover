import AppKit

/// Notices drags of files in any app, and ⇧ during them, with no Accessibility or Input
/// Monitoring permission (the approach #2's spike settled):
///
/// - A global monitor for left-mouse and modifier events. Global *mouse* monitors need no
///   permission, and they keep arriving during another app's drag. Key events never arrive
///   without permission, so there is no `keyDown` monitor: Esc is seen by the ring's panel.
/// - `NSPasteboard(name: .drag).changeCount` moves when any app starts a drag. A click,
///   ⇧-click or box-select never moves it, so "button down, and the count moved" is a drag.
/// - `NSEvent.pressedMouseButtons` and `NSEvent.modifierFlags`, polled at 120 Hz only while the
///   left button is down.
///
/// Never call `AXIsProcessTrusted`, `IOHIDCheckAccess` or `CGPreflightListenEventAccess` here:
/// each one records "denied" for the app in Input Monitoring, and nothing needs them.
@MainActor
final class DragWatcher {
    enum Event {
        /// A drag of files started. `files` are the dragged files when the drag pasteboard could
        /// be read at once; nil when they have to come from the ring's panel later.
        case dragStarted(shiftDown: Bool, files: [URL]?)
        /// ⇧ went down or up during the drag.
        case shift(down: Bool)
        /// The left button went up: the drag is over, or about to be.
        case buttonUp
    }

    var onEvent: ((Event) -> Void)?

    private enum Phase {
        case idle
        /// The button is down and no drag has started yet. `since`: when the drag pasteboard
        /// first changed without file URLs on it, if it has.
        case pressed(baseline: Int, since: Date?)
        case dragging(shift: Bool)
        /// A drag of something other than files (text, say): ignored until the button goes up.
        case otherDrag
    }

    private var phase = Phase.idle
    private let pasteboard = NSPasteboard(name: .drag)
    /// The drag pasteboard's count when the button was last up. The mouse-down event can arrive
    /// after the drag has started, so the count is compared with this, not read at mouse-down.
    private var idleBaseline: Int
    private var monitor: Any?
    private var timer: Timer?

    /// How long a changed drag pasteboard may stay without file URLs before the drag counts as
    /// one of something else: the source may write its items just after the count moves.
    private static let fileURLGrace: TimeInterval = 0.15

    init() {
        idleBaseline = pasteboard.changeCount
    }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .flagsChanged]
        ) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown, .leftMouseDragged:
            if case .idle = phase { phase = .pressed(baseline: idleBaseline, since: nil) }
            startPolling()
            tick()
        case .flagsChanged, .leftMouseUp:
            tick()
        default:
            break
        }
    }

    private func startPolling() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let buttonDown = NSEvent.pressedMouseButtons & 1 != 0
        let shift = NSEvent.modifierFlags.contains(.shift)

        switch phase {
        case .idle:
            break
        case .pressed(let baseline, let since):
            guard buttonDown else { phase = .idle; break }
            guard pasteboard.changeCount != baseline else { break }
            if let files = fileURLs() {
                phase = .dragging(shift: shift)
                ringLog.debug("Drag of \(files.count) file(s) started, ⇧ \(shift ? "held" : "up")")
                onEvent?(.dragStarted(shiftDown: shift, files: files.isEmpty ? nil : files))
            } else if let since, Date.now.timeIntervalSince(since) > Self.fileURLGrace {
                phase = .otherDrag
            } else if since == nil {
                phase = .pressed(baseline: baseline, since: .now)
            }
        case .dragging(let wasShift):
            if !buttonDown {
                phase = .idle
                onEvent?(.buttonUp)
            } else if shift != wasShift {
                phase = .dragging(shift: shift)
                onEvent?(.shift(down: shift))
            }
        case .otherDrag:
            if !buttonDown { phase = .idle }
        }

        if case .idle = phase, !buttonDown {
            idleBaseline = pasteboard.changeCount
            timer?.invalidate()
            timer = nil
        }
    }

    /// The dragged files, read from the drag pasteboard at drag start. Nil when the drag isn't
    /// one of files (yet); empty when it is, but the URLs can't be read.
    private func fileURLs() -> [URL]? {
        guard pasteboard.types?.contains(.fileURL) == true else { return nil }
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        return urls ?? []
    }
}
