import AppKit

/// Detects "a drag from another app is in progress and ⇧ was pressed after it started",
/// with no Accessibility or Input Monitoring permission.
///
/// Signals used (all permission-free):
/// - A global monitor for left-mouse events. It only wakes the poller; global *mouse* monitors
///   don't need Accessibility. We also subscribe to flagsChanged/keyDown/keyUp to log which of
///   them arrive without permissions.
/// - `NSPasteboard(name: .drag).changeCount`: it increments when any app starts a drag session.
///   A box-select or a plain click never changes it, so "button down + changeCount moved" means
///   "a real drag started".
/// - `NSEvent.modifierFlags` and `NSEvent.pressedMouseButtons` (class properties): the current
///   global state, readable by any process. Polled at 120 Hz only while the left button is down.
@MainActor
final class DragWatcher {
    enum Phase: CustomStringConvertible {
        case idle
        case pressed(baseline: Int)              // left button down, no drag session yet
        case dragging(shiftHeldAtStart: Bool)    // a drag session from some app is in progress
        case ringOpen
        case finishing(deadline: Date)           // button released with the ring open; waiting for drop callbacks
        case dragOver                            // drag ended (e.g. Esc) but the button is still down

        var description: String {
            switch self {
            case .idle: "idle"
            case .pressed(let b): "pressed(baseline: \(b))"
            case .dragging(let held): "dragging(shiftHeldAtStart: \(held))"
            case .ringOpen: "ringOpen"
            case .finishing: "finishing"
            case .dragOver: "dragOver"
            }
        }
    }

    private(set) var phase: Phase = .idle {
        didSet { say("phase \(oldValue) -> \(phase)") }
    }

    private let ring: RingPanelController
    private let dragPasteboard = NSPasteboard(name: .drag)
    private var idleBaseline: Int
    private var monitor: Any?
    private var timer: Timer?
    private var lastShift = false
    private var eventCounts: [String: Int] = [:]

    init(ring: RingPanelController) {
        self.ring = ring
        self.idleBaseline = NSPasteboard(name: .drag).changeCount
        ring.onDragFinished = { [weak self] reason in self?.dragFinished(reason) }
    }

    func start() {
        var mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseUp, .leftMouseDragged, .flagsChanged]
        // Opt-in experiment: key events need Accessibility/Input Monitoring and never arrive without them.
        let keys = UserDefaults.standard.bool(forKey: "monitorKeyEvents")
        if keys { mask.formUnion([.keyDown, .keyUp]) }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.handleGlobal(event) }
        }
        say("global monitor installed=\(monitor != nil) keyEvents=\(keys); drag pasteboard changeCount=\(idleBaseline)")
    }

    // MARK: - Global events

    private func handleGlobal(_ event: NSEvent) {
        let name = Self.name(of: event.type)
        eventCounts[name, default: 0] += 1
        switch event.type {
        case .leftMouseDown:
            eventCounts = [name: 1]
            say("global leftMouseDown at \(NSEvent.mouseLocation) flags=\(Self.describe(event.modifierFlags)) dragCC=\(dragPasteboard.changeCount)")
            if case .idle = phase { phase = .pressed(baseline: idleBaseline) }
            startPolling()
        case .leftMouseDragged:
            if eventCounts[name] == 1 { say("global leftMouseDragged (first of this press)") }
            if case .idle = phase, NSEvent.pressedMouseButtons & 1 != 0 { phase = .pressed(baseline: idleBaseline) }
            startPolling()
        case .flagsChanged:
            say("global flagsChanged flags=\(Self.describe(event.modifierFlags)) keyCode=\(event.keyCode) phase=\(phase)")
            tick(source: "flagsChanged")
        case .keyDown, .keyUp:
            say("global \(name) keyCode=\(event.keyCode)")
        case .leftMouseUp:
            say("global leftMouseUp; global events this press: \(eventCounts)")
        default:
            break
        }
    }

    // MARK: - Polling while the button is down

    private func startPolling() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick(source: "poll") }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        say("polling started")
    }

    private func stopPolling() {
        guard let timer else { return }
        timer.invalidate()
        self.timer = nil
        say("polling stopped")
    }

    private func tick(source: String) {
        let leftDown = NSEvent.pressedMouseButtons & 1 != 0
        let shift = NSEvent.modifierFlags.contains(.shift)
        let changeCount = dragPasteboard.changeCount
        if shift != lastShift {
            say("[\(source)] NSEvent.modifierFlags shift=\(shift) leftDown=\(leftDown) phase=\(phase)")
            lastShift = shift
        }

        switch phase {
        case .idle:
            break
        case .pressed(let baseline):
            if !leftDown {
                phase = .idle
            } else if changeCount != baseline {
                say("DRAG DETECTED: drag pasteboard changeCount \(baseline) -> \(changeCount); shift held at start=\(shift)")
                phase = .dragging(shiftHeldAtStart: shift)
            }
        case .dragging(let heldAtStart):
            if !leftDown {
                phase = .idle
            } else if heldAtStart {
                if !shift {
                    say("shift released after being held at drag start; the next press opens the ring")
                    phase = .dragging(shiftHeldAtStart: false)
                }
            } else if shift {
                say("SHIFT PRESSED MID-DRAG -> open ring at \(NSEvent.mouseLocation)")
                phase = .ringOpen
                ring.open(at: NSEvent.mouseLocation)
            }
        case .ringOpen:
            if !leftDown {
                say("button released with ring open; waiting for drop callbacks")
                phase = .finishing(deadline: Date().addingTimeInterval(1))
            } else if !shift {
                say("SHIFT RELEASED -> close ring, drag continues")
                ring.close(reason: "shift released")
                phase = .dragging(shiftHeldAtStart: false)
            }
        case .finishing(let deadline):
            if Date() > deadline {
                ring.close(reason: "timeout after mouse up")
                phase = .idle
            }
        case .dragOver:
            if !leftDown { phase = .idle }
        }

        if case .idle = phase, !leftDown {
            idleBaseline = changeCount
            stopPolling()
        }
    }

    /// Called by the panel when the drag session is over from its point of view
    /// (drop performed, drop refused, Esc).
    private func dragFinished(_ reason: String) {
        switch phase {
        case .ringOpen, .finishing:
            ring.close(reason: reason)
            phase = NSEvent.pressedMouseButtons & 1 != 0 ? .dragOver : .idle
        default:
            break
        }
    }

    // MARK: - Helpers

    private static func name(of type: NSEvent.EventType) -> String {
        switch type {
        case .leftMouseDown: "leftMouseDown"
        case .leftMouseUp: "leftMouseUp"
        case .leftMouseDragged: "leftMouseDragged"
        case .flagsChanged: "flagsChanged"
        case .keyDown: "keyDown"
        case .keyUp: "keyUp"
        default: "type\(type.rawValue)"
        }
    }

    static func describe(_ flags: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.command) { parts.append("⌘") }
        return parts.isEmpty ? "none" : parts.joined()
    }
}
