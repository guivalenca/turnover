import Foundation
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
        /// What the dragged files can be converted to, or the same offers with newer estimates.
        /// Send it as soon as the files are known (at drag start if the drag pasteboard can be
        /// read then, otherwise when the open ring first sees the drag), then on every update.
        case offers(Offers)
        /// The pointer moved over the open ring: its offset from the ring's centre, in points,
        /// x to the right and y down (screen coordinates, as the angles are).
        case pointer(x: Double, y: Double)
        /// The files were dropped on the open ring.
        case drop
        /// Esc: the system cancelled the drag. The app sees it as the open ring's drag leaving
        /// while the button is still down, after the drag image slides back.
        case escape
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

    /// The ring's entries while it is open and the dragged files are known; empty otherwise.
    public var entries: [Entry] {
        guard phase == .open, let offers else { return [] }
        return Self.layout(offers)
    }

    /// The entry a drop would convert to: the one whose arc the pointer is in, if the pointer is
    /// between the hub and the outer edge.
    public var highlighted: Entry? {
        guard let pointer else { return nil }
        let distance = (pointer.x * pointer.x + pointer.y * pointer.y).squareRoot()
        guard distance >= Self.hubRadius, distance <= Self.outerRadius else { return nil }
        let angle = atan2(pointer.y, pointer.x) * 180 / .pi
        return entries.first { $0.arc.contains(angle) }
    }

    /// Inside this distance from the centre, the pointer is on the hub: nothing is highlighted.
    public static let hubRadius = 38.0
    /// Beyond this distance from the centre, the pointer is off the ring: nothing is highlighted.
    public static let outerRadius = 195.0

    /// The dragged files' offers, once known.
    private var offers: Offers?
    /// The pointer's offset from the centre, once it has moved over the open ring.
    private var pointer: (x: Double, y: Double)?

    /// ⇧ was held when the drag started and hasn't been released since: it doesn't count.
    private var shiftHeldSinceDragStart = false

    public init() {}

    public mutating func send(_ event: Event) {
        switch event {
        case .dragStarted(let shiftDown):
            phase = .dragging
            shiftHeldSinceDragStart = shiftDown
            offers = nil
            outcome = nil
        case .shift(let down):
            if !down { shiftHeldSinceDragStart = false }
            if down, phase == .dragging, !shiftHeldSinceDragStart {
                phase = .open
                // The ring opens centred on the pointer.
                pointer = (0, 0)
            }
            if !down, phase == .open { phase = .dragging }
        case .offers(let offers):
            self.offers = offers
        case .pointer(let x, let y):
            pointer = (x, y)
        case .drop:
            guard phase == .open else { return }
            outcome = highlighted.map { .convert($0.choices) } ?? .cancel
            phase = .idle
        case .escape:
            if phase == .open { outcome = .cancel }
            phase = .idle
        case .dragEnded:
            phase = .idle
        }
    }
}
