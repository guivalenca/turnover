import Foundation
import TurnoverKit

extension RingModel {
    /// The pointer resting on a format in a mixed ring: it is added at `deadline` unless the
    /// pointer leaves it first.
    public struct Rest: Sendable, Hashable {
        /// The entry being rested on.
        public let entry: Entry.ID
        /// When the rest began, on the `time` clock; nil until the first `time` after it.
        public let since: TimeInterval?
        /// When the entry is added: `since` plus the rest delay.
        public let deadline: TimeInterval?
    }

    /// A format added by resting on it, with its name for the caption.
    struct Addition: Sendable, Hashable {
        let choice: Choice
        /// "PNG", "MP4"; a JPEG quality fanned out by ⌥ names its percentage: "JPEG 100%";
        /// a smaller MP4's, its name: "Smaller (Medium)".
        let label: String
    }

    /// After every event: starts, carries on or ends the rest on the highlighted entry, and adds
    /// it once the pointer has rested on it for `restDelay`.
    mutating func settleRest() {
        guard isMixed, let entry = highlighted, !entry.isAdded else {
            rest = nil
            return
        }
        let since = rest?.entry == entry.id ? rest?.since ?? now : now
        rest = Rest(entry: entry.id, since: since, deadline: since.map { $0 + restDelay })
        guard let deadline = rest?.deadline, let now, now >= deadline else { return }
        add(entry)
        rest = nil
    }

    /// What a drop on `entry` converts: everything added so far, plus the entry, which wins
    /// within its own kind of file. The prototype's rule:
    ///
    /// ```js
    /// function commit(entry) {
    ///   const parts = { ...ring.locks };              // kind -> target, e.g. { image: PNG }
    ///   entry.parts.forEach(p => (parts[p.kind] = p));
    ///   return Object.values(parts);                  // e.g. [PNG for images, MP4 for videos]
    /// }
    /// ```
    func choices(droppingOn entry: Entry) -> [Choice] {
        var merged = added
        for choice in entry.choices {
            if let index = merged.firstIndex(where: { $0.kind == choice.kind }) {
                merged[index] = choice
            } else {
                merged.append(choice)
            }
        }
        return merged
    }

    /// Adds `entry`, replacing what was added for its kind of file.
    private mutating func add(_ entry: Entry) {
        let choice = entry.choices[0]
        let label = entry.quality.map { quality in
            switch quality {
            case .jpeg(let quality):
                String(localized: "\(choice.format.name) \(quality.percent)%", bundle: .ringModel,
                       comment: "A JPEG quality added by resting on it, in the caption: “JPEG 100%”.")
            case .video(let quality):
                String(localized: "\(choice.format.shortName) (\(quality.name))", bundle: .ringModel,
                       comment: "A smaller MP4's quality added by resting on it, in the caption: “Smaller (Medium)”.")
            }
        } ?? choice.format.shortName
        let addition = Addition(choice: choice, label: label)
        if let index = additions.firstIndex(where: { $0.choice.kind == choice.kind }) {
            additions[index] = addition
        } else {
            additions.append(addition)
        }
    }
}
