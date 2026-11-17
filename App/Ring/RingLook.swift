import Foundation
import RingModel

/// What the glass ring shows, as `RingView` draws it. It is built from the model in one place,
/// `init(_:)`, so the view draws whatever state the model exposes; Debug previews build it
/// directly (`RingPreview`).
struct RingLook: Equatable {
    struct Entry: Equatable {
        /// "PNG", "JPEG", "MP4", or a JPEG quality fanned out by ⌥ ("Best").
        var title: String
        /// Its estimate: "19 MB", "~19 MB", "About 5 s"; "…" until known.
        var subtitle: String
        /// Degrees clockwise from the right, -90° at the top.
        var angle: Double
        /// The angles it owns (its highlight's shape), clockwise from `start` to `end`.
        var arcStart: Double
        var arcEnd: Double
        /// A fanned-out JPEG quality that is the stored default: marked with a dot.
        var isDefault = false
        /// Added by resting on it: tinted, with a ✓.
        var isAdded = false
    }

    struct Hub: Equatable {
        /// "PNG", "PNG + MP4", "JPEG", or the file count ("3").
        var title: String
        /// "19 MB", "2 files", "quality", "images".
        var detail: String
    }

    var entries: [Entry] = []
    /// The index of the entry a drop converts to.
    var highlighted: Int?
    var hub: Hub?
    /// The line under the ring, for mixed drags only.
    var caption: String?
    /// The pointer is resting on the highlighted entry, which is added after this long.
    var restingFor: TimeInterval?
}

extension RingLook {
    init(_ model: RingModel) {
        let entries = model.entries
        self.entries = entries.map {
            Entry(title: $0.title, subtitle: $0.subtitle, angle: $0.angle, arcStart: $0.arc.start, arcEnd: $0.arc.end,
                  isDefault: $0.isDefault, isAdded: $0.isAdded)
        }
        let highlightedEntry = model.highlighted
        highlighted = highlightedEntry.flatMap { entry in entries.firstIndex { $0.id == entry.id } }
        hub = model.hub.map { Hub(title: $0.title, detail: $0.detail) }
        caption = model.caption
        // Resting on the highlighted entry adds it at the deadline: the tint fills until then.
        if let rest = model.rest, rest.entry == highlightedEntry?.id, let since = rest.since, let deadline = rest.deadline {
            restingFor = max(0, deadline - since)
        }
    }

    /// Entries that differ only in their estimates keep their labels; anything else lays the
    /// ring out again.
    func hasSameLayout(as other: RingLook) -> Bool {
        entries.map(\.title) == other.entries.map(\.title) && entries.map(\.angle) == other.entries.map(\.angle)
    }
}
