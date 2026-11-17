import TurnoverKit

extension RingModel {
    /// One format on the ring.
    public struct Entry: Sendable, Hashable {
        /// The format: "PNG", "JPEG" or "MP4".
        public let title: String
        /// Its estimate: "19 MB" (measured), "~19 MB", "Instant", "About 5 s"; "…" until known.
        public var subtitle: String { estimate?.label ?? "…" }
        /// For every file it converts together; nil until estimated.
        public let estimate: Estimate?
        /// Where it sits, in degrees clockwise from the right (screen coordinates, y down):
        /// -90° is the top, 180° the left.
        public let angle: Double
        /// The angles it owns, halfway to each neighbour: the pointer anywhere in it highlights it.
        public let arc: Arc
        /// What a drop on it converts.
        public let choices: [Choice]
    }

    /// A stretch of the circle, clockwise from `start` to `end`, in degrees (`end - start` is at
    /// most 360; either may be outside -180…180).
    public struct Arc: Sendable, Hashable {
        public let start: Double
        public let end: Double

        public init(start: Double, end: Double) {
            self.start = start
            self.end = end
        }

        /// Whether `angle`, in degrees, falls in the arc, whatever turn it is given in.
        public func contains(_ angle: Double) -> Bool {
            var offset = (angle - start).truncatingRemainder(dividingBy: 360)
            if offset < 0 { offset += 360 }
            return offset <= end - start
        }
    }

    /// A single entry sits at the top; two sit left and right, in display order (PNG left, JPEG
    /// right). More (a mixed drag) are spread evenly from the top for now: #12 lays out mixed
    /// drags, images on the left and videos on the right.
    static func layout(_ offers: Offers) -> [Entry] {
        let targets = offers.targets
        let angles: [Double] = switch targets.count {
        case 1: [-90]
        case 2: [180, 0]
        default: targets.indices.map { -90 + Double($0) * 360 / Double(targets.count) }
        }
        return zip(targets, angles).map { target, angle in
            Entry(title: target.format.name, estimate: target.estimate, angle: angle,
                  arc: arc(around: angle, among: angles), choices: [Choice(target)])
        }
    }

    /// The arc halfway to the nearest entry on each side; the whole circle for a lone entry.
    private static func arc(around angle: Double, among angles: [Double]) -> Arc {
        let others = angles.filter { $0 != angle }
        guard !others.isEmpty else { return Arc(start: angle - 180, end: angle + 180) }
        // How far clockwise each other entry is, in (0, 360).
        let clockwise = others.map { other in
            let d = (other - angle).truncatingRemainder(dividingBy: 360)
            return d <= 0 ? d + 360 : d
        }
        let next = clockwise.min()!, previous = 360 - clockwise.max()!
        return Arc(start: angle - previous / 2, end: angle + next / 2)
    }
}
