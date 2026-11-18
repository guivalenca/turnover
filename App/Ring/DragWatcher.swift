import AppKit
import TurnoverAppCore

/// Notices drags of files in any app, and ⇧ and ⌥ during them, with no Accessibility or Input
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
        /// A drag of files started, with ⇧ and ⌥ as they were then. `files` are the dragged files
        /// when the drag pasteboard could be read at once; nil when they have to come from the
        /// ring's panel later. `source` is where the button went down: the Desktop, a Finder
        /// window or somewhere else.
        case dragStarted(shiftDown: Bool, optionDown: Bool, files: [URL]?, source: DragSource)
        /// ⇧ went down or up during the drag.
        case shift(down: Bool)
        /// ⌥ went down or up during the drag.
        case option(down: Bool)
        /// The left button went up: the drag is over, or about to be.
        case buttonUp
    }

    var onEvent: ((Event) -> Void)?

    private enum Phase {
        case idle
        /// The button is down and no drag has started yet. `at`: where it went down, in AppKit
        /// screen coordinates. `since`: when the drag pasteboard first changed without file URLs
        /// on it, if it has.
        case pressed(baseline: Int, at: NSPoint, since: Date?)
        case dragging(shift: Bool, option: Bool)
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
            if case .idle = phase { phase = .pressed(baseline: idleBaseline, at: NSEvent.mouseLocation, since: nil) }
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
        let flags = NSEvent.modifierFlags
        let shift = flags.contains(.shift), option = flags.contains(.option)

        switch phase {
        case .idle:
            break
        case .pressed(let baseline, let point, let since):
            guard buttonDown else { phase = .idle; break }
            guard pasteboard.changeCount != baseline else { break }
            if let files = fileURLs() {
                phase = .dragging(shift: shift, option: option)
                let source = DragSource.current(of: files, at: point)
                ringLog.debug("Drag of \(files.count) file(s) started from \(String(describing: source), privacy: .public), ⇧ \(shift ? "held" : "up"), ⌥ \(option ? "held" : "up")")
                onEvent?(.dragStarted(shiftDown: shift, optionDown: option, files: files.isEmpty ? nil : files, source: source))
            } else if let since, Date.now.timeIntervalSince(since) > Self.fileURLGrace {
                phase = .otherDrag
            } else if since == nil {
                phase = .pressed(baseline: baseline, at: point, since: .now)
            }
        case .dragging(let wasShift, let wasOption):
            if !buttonDown {
                phase = .idle
                onEvent?(.buttonUp)
                break
            }
            phase = .dragging(shift: shift, option: option)
            if option != wasOption { onEvent?(.option(down: option)) }
            if shift != wasShift { onEvent?(.shift(down: shift)) }
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
