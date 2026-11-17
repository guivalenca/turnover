import TurnoverKit

/// The drag + ⇧ ring as a state machine, with no UI: the app feeds it what happens during a drag
/// of files, and draws and acts on what it says.
public struct RingModel: Sendable {
    /// Where the gesture is.
    public enum Phase: Sendable, Hashable {
        /// No drag of files in progress.
        case idle
        /// Files are being dragged and the ring is closed.
        case dragging
        /// The ring is open: it catches the drop everywhere on screen.
        case open
    }

    /// What happens during a drag, in the order it happens.
    public enum Event: Sendable, Hashable {
        /// A drag of files started. `shiftDown`: ⇧ was already held, so it doesn't open the ring
        /// until it is released and pressed again.
        case dragStarted(shiftDown: Bool)
        /// ⇧ went down or up.
        case shift(down: Bool)
        /// The drag ended without a drop on the ring: dropped somewhere else while the ring was
        /// closed, or the drag session finished some other way.
        case dragEnded
    }

    /// How a drag that ended on the open ring turned out.
    public enum Outcome: Sendable, Hashable {
        /// Convert: one choice per kind of file.
        case convert([Choice])
        /// Nothing happens, and nothing moves.
        case cancel
    }

    public private(set) var phase: Phase = .idle

    /// Set when a drag ends with the ring open; nil until then, and again from the next drag.
    public private(set) var outcome: Outcome?

    /// ⇧ was held when the drag started and hasn't been released since: it doesn't count.
    private var shiftHeldSinceDragStart = false

    public init() {}

    public mutating func send(_ event: Event) {
        switch event {
        case .dragStarted(let shiftDown):
            phase = .dragging
            shiftHeldSinceDragStart = shiftDown
        case .shift(let down):
            if !down { shiftHeldSinceDragStart = false }
            if down, phase == .dragging, !shiftHeldSinceDragStart { phase = .open }
            if !down, phase == .open { phase = .dragging }
        case .dragEnded:
            phase = .idle
        }
    }
}
