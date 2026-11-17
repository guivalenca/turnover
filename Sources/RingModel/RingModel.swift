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
        /// ⌥ went down or up. Send it whenever it changes during a drag, and its state at drag
        /// start: held while the ring is open, it fans JPEG out into its qualities.
        case option(down: Bool)
        /// What the dragged files can be converted to, or the same offers with newer estimates.
        /// Send it as soon as the files are known (at drag start if the drag pasteboard can be
        /// read then, otherwise when the open ring first sees the drag), then on every update.
        case offers(Offers)
        /// The pointer moved over the open ring: its offset from the ring's centre, in points,
        /// x to the right and y down (screen coordinates, as the angles are).
        case pointer(x: Double, y: Double)
        /// The time, in seconds on a steady clock (the app sends `ProcessInfo.systemUptime`).
        /// Send it before every `pointer`, and again at `rest?.deadline`: resting on a format
        /// that long adds it.
        case time(TimeInterval)
        /// The files were dropped on the open ring.
        case drop
        /// Esc: the system cancelled the drag. The app sees it as the open ring's drag leaving
        /// while the button is still down, after the drag image slides back.
        case escape
        /// The drag ended without a drop on an entry: dropped somewhere else while the ring was
        /// closed, or off the ring's entries while it was open (which cancels).
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

    /// Why nothing is offered, shown briefly instead of the ring when ⇧ is pressed during a drag
    /// of files Turnover can't convert, e.g. "lease.pdf: not an image or a video (PDF document)".
    /// Nil once ⇧ is released or the drag ends.
    public private(set) var hint: String?

    /// The ring's entries while it is open and the dragged files are known; empty otherwise.
    public var entries: [Entry] {
        guard phase == .open, let offers else { return [] }
        return Self.layout(offers, fannedOut: isFannedOut, added: added)
    }

    /// How long the pointer rests on a format to add it: the system's spring-loading delay.
    public let restDelay: TimeInterval

    /// The formats added by resting on them, at most one per kind of file, in the order they
    /// were added. A drop converts these plus the format dropped on, which wins within its kind.
    public var added: [Choice] { additions.map(\.choice) }

    /// The pointer resting on a format that resting adds, in a mixed ring; nil otherwise.
    public internal(set) var rest: Rest?

    /// ⌥ is held over the open ring and JPEG is offered: JPEG is fanned out into its qualities.
    public var isFannedOut: Bool {
        guard phase == .open, optionDown, let offers else { return false }
        return offers.targets.contains { $0.format == .jpeg }
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

    /// What the hub says while the ring is open and the files are known: what a drop on the
    /// highlighted entry converts to, or how many files are dragged.
    public var hub: Hub? {
        guard phase == .open, let offers else { return nil }
        guard let entry = highlighted, let choice = entry.choices.first else {
            if isFannedOut { return Hub(title: "JPEG", detail: "quality", text: "JPEG quality") }
            let files = offers.groups.flatMap(\.files)
            let kinds = Set(offers.groups.map(\.kind))
            let noun = kinds.count == 1 ? Self.noun(kinds.first!, count: files.count) : (files.count == 1 ? "file" : "files")
            return Hub(title: "\(files.count)", detail: noun, text: "\(files.count) \(noun)")
        }
        // Several formats (one added, say): their names and how many files they convert.
        let dropped = choices(droppingOn: entry)
        if dropped.count > 1 {
            let title = dropped.map(\.format.name).joined(separator: " + ")
            let count = dropped.map(\.files.count).reduce(0, +)
            let detail = "\(count) file\(count == 1 ? "" : "s")"
            return Hub(title: title, detail: detail, text: "\(title) · \(detail)")
        }
        // One format: its size or time, or how many files it converts until that is known.
        var detail = entry.estimate?.label ?? "\(choice.files.count) \(Self.noun(choice.kind, count: choice.files.count))"
        // A JPEG quality: "JPEG", "Best · 5.2 MB".
        if let quality = entry.quality { detail = "\(quality.name) · \(detail)" }
        let title = choice.format.name
        return Hub(title: title, detail: detail, text: "\(title) · \(detail)")
    }

    /// The line under the ring, for images and videos dragged together only: how to add a
    /// format, then what has been added ("PNG added · drop to convert"). Nil otherwise.
    public var caption: String? {
        guard isMixed else { return nil }
        guard !additions.isEmpty else { return "Rest on a format to add it, then drop on another" }
        return additions.map(\.label).joined(separator: " + ") + " added · drop to convert"
    }

    /// The open ring offers formats for more than one kind of file: rest-to-add applies.
    var isMixed: Bool {
        guard phase == .open, let offers else { return false }
        return offers.groups.count > 1
    }

    /// The text in the ring's centre.
    public struct Hub: Sendable, Hashable {
        /// The large line: what a drop converts to ("PNG", "PNG + MP4", "JPEG"), or the file
        /// count ("3"), or "JPEG" while ⌥ fans it out.
        public let title: String
        /// The small line under it: the estimate ("19 MB"), the quality and its estimate
        /// ("Best · 5.2 MB"), the files converted ("3 files"), what is counted ("images"), or
        /// "quality".
        public let detail: String
        /// Both on one line, for logs and accessibility: "PNG · 19 MB", "PNG + MP4 · 3 files",
        /// "3 images", "JPEG quality".
        public let text: String
    }

    private static func noun(_ kind: SourceFile.Kind, count: Int) -> String {
        (kind == .video ? "video" : "image") + (count == 1 ? "" : "s")
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
    /// ⌥ is held.
    private var optionDown = false
    /// The last time sent, if any.
    var now: TimeInterval?
    /// What resting added, with how the caption names it.
    var additions: [Addition] = []

    /// `restDelay`: the system's spring-loading delay, `com.apple.springing.delay`.
    public init(restDelay: TimeInterval = 0.5) {
        self.restDelay = restDelay
    }

    public mutating func send(_ event: Event) {
        defer { settleRest() }
        switch event {
        case .dragStarted(let shiftDown):
            phase = .dragging
            shiftHeldSinceDragStart = shiftDown
            offers = nil
            outcome = nil
            hint = nil
        case .shift(down: true):
            guard phase == .dragging, !shiftHeldSinceDragStart else { return }
            open()
        case .shift(down: false):
            shiftHeldSinceDragStart = false
            hint = nil
            if phase == .open { phase = .dragging }
        case .option(let down):
            optionDown = down
        case .offers(let offers):
            self.offers = offers
            // Nothing to convert: a hint instead of the ring, and the drag goes on as usual.
            if phase == .open, let reason = offers.reason {
                phase = .dragging
                hint = reason
            }
        case .pointer(let x, let y):
            pointer = (x, y)
        case .time(let time):
            now = time
        case .drop:
            guard phase == .open else { return }
            outcome = highlighted.map { .convert(choices(droppingOn: $0)) } ?? .cancel
            phase = .idle
        case .escape, .dragEnded:
            if phase == .open { outcome = .cancel }
            phase = .idle
            hint = nil
        }
    }

    /// ⇧ pressed mid-drag: the ring opens centred on the pointer, unless the files are known to
    /// have nothing to convert.
    private mutating func open() {
        if let reason = offers?.reason {
            hint = reason
            return
        }
        phase = .open
        pointer = (0, 0)
        additions = []
        rest = nil
    }
}
