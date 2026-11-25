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
        /// start: held while the ring is open, it fans JPEG and a smaller MP4 out into their qualities.
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

    /// The formats with qualities (JPEG, a smaller MP4) are fanned out into them: ⌥ is held over
    /// the open ring, or a smaller MP4 is all there is to choose.
    public var isFannedOut: Bool {
        guard phase == .open, let offers else { return false }
        if offers.targets.map(\.format) == [.smaller] { return true }
        return optionDown && offers.targets.contains { !$0.format.qualities.isEmpty }
    }

    /// The entry a drop would convert to: the one whose arc the pointer is in, if the pointer is
    /// on the drawn band, between the hub and the outer edge (`RingGeometry`'s radii).
    public var highlighted: Entry? {
        guard let pointer else { return nil }
        let distance = (pointer.x * pointer.x + pointer.y * pointer.y).squareRoot()
        guard distance >= RingGeometry.hubRadius, distance <= RingGeometry.outerRadius else { return nil }
        let angle = atan2(pointer.y, pointer.x) * 180 / .pi
        return entries.first { $0.arc.contains(angle) }
    }

    /// What the hub says while the ring is open and the files are known: what a drop on the
    /// highlighted entry converts to, or how many files are dragged. For an image dragged out of
    /// a web page, what it is instead of a count: "WebP", "1600 × 1067".
    public var hub: Hub? {
        guard phase == .open, let offers else { return nil }
        guard let entry = highlighted, let choice = entry.choices.first else {
            let fannedOut = isFannedOut ? offers.targets.filter { !$0.format.qualities.isEmpty } : []
            if fannedOut.count == 1, let smaller = fannedOut.first, smaller.format == .smaller {
                // What the qualities are of: "Smaller", "1 video".
                let detail = Self.files(smaller.files.count, of: smaller.kind)
                return Hub(title: smaller.format.shortName, detail: detail, text: Self.line(smaller.format.shortName, detail))
            }
            // Both at once (a mixed ring): the file count, as with neither.
            if fannedOut.count == 1 {
                return Hub(title: OutputFormat.jpeg.name,
                           detail: String(localized: "quality", bundle: .ringModel,
                                          comment: "The hub's small line under “JPEG” while ⌥ fans out JPEG's qualities."),
                           text: String(localized: "JPEG quality", bundle: .ringModel,
                                        comment: "The hub while ⌥ fans out JPEG's qualities, on one line."))
            }
            if let original = offers.original {
                // A size in pixels isn't a count: no grouping separators, in any language.
                let detail = if let width = original.width, let height = original.height {
                    "\(width) × \(height)"
                } else {
                    Self.noun(of: .image, count: 1)
                }
                return Hub(title: original.typeName, detail: detail, text: Self.line(original.typeName, detail))
            }
            let count = offers.groups.flatMap(\.files).count
            let kinds = Set(offers.groups.map(\.kind))
            let kind = kinds.count == 1 ? kinds.first : nil
            return Hub(title: "\(count)", detail: Self.noun(of: kind, count: count), text: Self.files(count, of: kind))
        }
        // Several formats (one added, say): their names and how many files they convert.
        let dropped = choices(droppingOn: entry)
        if dropped.count > 1 {
            let title = dropped.map(\.format.shortName).joined(separator: " + ")
            let detail = Self.files(dropped.map(\.files.count).reduce(0, +), of: nil)
            return Hub(title: title, detail: detail, text: Self.line(title, detail))
        }
        // A smaller MP4's quality: "Medium", "~12 MB".
        if case .video(let quality) = entry.quality {
            let detail = entry.estimate?.label ?? Self.files(choice.files.count, of: choice.kind)
            return Hub(title: quality.name, detail: detail, text: Self.line(quality.name, detail))
        }
        // One format: its size or time, or how many files it converts until that is known.
        var detail = entry.estimate?.label ?? Self.files(choice.files.count, of: choice.kind)
        // A JPEG quality: "JPEG", "Best · 5.2 MB".
        if let quality = entry.quality { detail = Self.line(quality.name, detail) }
        // Original: the image's own format rather than "Original", "WebP" over "212 KB".
        let title = choice.format == .original ? offers.original?.typeName ?? choice.format.name : choice.format.shortName
        return Hub(title: title, detail: detail, text: Self.line(title, detail))
    }

    /// The line under the ring, for images and videos dragged together only: how to add a
    /// format, then what has been added ("PNG added · drop to convert"). Nil otherwise.
    public var caption: String? {
        guard isMixed else { return nil }
        guard !additions.isEmpty else {
            return String(localized: "Rest on a format to add it, then drop on another", bundle: .ringModel,
                          comment: "Under the ring when photos and videos are dragged together.")
        }
        let added = additions.map(\.label).joined(separator: " + ")
        return String(localized: "\(added) added · drop to convert", bundle: .ringModel,
                      comment: "Under the ring once formats are added by resting on them: “PNG + MP4 added · drop to convert”.")
    }

    /// The open ring offers formats for more than one kind of file: rest-to-add applies.
    var isMixed: Bool {
        guard phase == .open, let offers else { return false }
        return offers.groups.count > 1
    }

    /// The text in the ring's centre.
    public struct Hub: Sendable, Hashable {
        /// The large line: what a drop converts to ("PNG", "PNG + MP4", "JPEG"), or the file
        /// count ("3"), or "JPEG" while ⌥ fans it out; "WebP" for an image dragged out of a web
        /// page, over nothing or over Original.
        public let title: String
        /// The small line under it: the estimate ("19 MB"), the quality and its estimate
        /// ("Best · 5.2 MB"), the files converted ("3 files"), what is counted ("images"), or
        /// "quality".
        public let detail: String
        /// Both on one line, for logs and accessibility: "PNG · 19 MB", "PNG + MP4 · 3 files",
        /// "3 images", "JPEG quality".
        public let text: String
    }

    /// "3 images", "1 video", or "2 files" for nil (both kinds).
    private static func files(_ count: Int, of kind: SourceFile.Kind?) -> String {
        switch kind {
        case .image: String(localized: "\(count) images", bundle: .ringModel, comment: "How many images a drop converts.")
        case .video: String(localized: "\(count) videos", bundle: .ringModel, comment: "How many videos a drop converts.")
        default: String(localized: "\(count) files", bundle: .ringModel, comment: "How many files a drop converts.")
        }
    }

    /// The noun alone, agreeing with `count`, for the hub's small line under the count.
    private static func noun(of kind: SourceFile.Kind?, count: Int) -> String {
        let comment: StaticString = "The hub's small line under the count of dragged files: the noun alone, agreeing with the count above it."
        return switch kind {
        case .image: String(localized: "images under a count of \(count)", bundle: .ringModel, comment: comment)
        case .video: String(localized: "videos under a count of \(count)", bundle: .ringModel, comment: comment)
        default: String(localized: "files under a count of \(count)", bundle: .ringModel, comment: comment)
        }
    }

    /// Two parts of the hub on one line: "PNG · 19 MB", "Best · 5.2 MB".
    static func line(_ first: String, _ second: String) -> String {
        String(localized: "\(first) · \(second)", bundle: .ringModel,
               comment: "Two parts of the hub on one line: the format and its size, “PNG · 19 MB”.")
    }

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
