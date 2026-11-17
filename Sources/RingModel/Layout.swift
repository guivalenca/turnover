import TurnoverKit

extension RingModel {
    /// One format on the ring.
    public struct Entry: Sendable, Hashable {
        /// The format ("PNG", "JPEG", "MP4"), or a JPEG quality ⌥ fanned out ("Best", "High",
        /// "Small").
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
        /// The JPEG quality it stands for when ⌥ fans JPEG out ("Best", say); nil for a format.
        public let quality: JPEGQuality?
        /// A JPEG quality fanned out by ⌥ that is the stored default: it is marked.
        public let isDefault: Bool
        /// Added by resting on it: it stays tinted, with a ✓.
        public let isAdded: Bool

        /// Which format, or JPEG quality, of which kind of file it is, whatever its estimate.
        public var id: ID { ID(kind: choices[0].kind, format: choices[0].format, quality: quality) }

        public struct ID: Sendable, Hashable {
            public let kind: SourceFile.Kind
            public let format: OutputFormat
            /// Set for a JPEG quality fanned out by ⌥; nil for JPEG itself.
            public let quality: JPEGQuality?
        }
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

    /// One kind of file: a single entry sits at the top; two sit left and right, in display
    /// order (PNG left, JPEG right). Images and videos together: images on the left, centred on
    /// 180° and 74° apart; videos on the right, at 0°. With ⌥, JPEG's qualities fan out around
    /// where JPEG was: 54° apart, or 52° in a mixed ring. Angles are in (-180, 180].
    static func layout(_ offers: Offers, fannedOut: Bool, added: [Choice]) -> [Entry] {
        let groups = offers.groups.map { group in
            (kind: group.kind, spots: group.targets.flatMap { spots(for: $0, fannedOut: fannedOut) })
        }
        let angles: [Double]
        if groups.count == 1 {
            let spots = groups[0].spots
            if spots.contains(where: { $0.preset != nil }) {
                // JPEG's qualities around where JPEG was: the right, or the top if JPEG was alone.
                let others = spots.filter { $0.preset == nil }.count
                angles = others == 1 ? [180] + spread(3, around: 0, step: 54) : spread(3, around: -90, step: 54)
            } else {
                angles = spots.count == 1 ? [-90] : [180, 0]
            }
        } else {
            angles = groups.flatMap { group in
                group.kind == .video
                    ? spread(group.spots.count, around: 0, step: 74)
                    : spread(group.spots.count, around: 180, step: fannedOut ? 52 : 74)
            }
        }
        let spots = groups.flatMap(\.spots)
        let placed = angles.map(normalized)
        return zip(spots, placed).map { spot, angle in
            Entry(title: spot.title, estimate: spot.estimate, angle: angle,
                  arc: arc(around: angle, among: placed), choices: spot.choices,
                  quality: spot.preset, isDefault: spot.isDefault, isAdded: added.contains(spot.choices[0]))
        }
    }

    /// `angle` turned into (-180, 180].
    private static func normalized(_ angle: Double) -> Double {
        let turned = angle.truncatingRemainder(dividingBy: 360)
        return turned > 180 ? turned - 360 : turned <= -180 ? turned + 360 : turned
    }

    /// What an entry shows and converts, before it is placed.
    private struct Spot {
        let title: String
        let estimate: Estimate?
        let choices: [Choice]
        /// The JPEG quality it stands for, when JPEG is fanned out.
        let preset: JPEGQuality?
        var isDefault = false
    }

    /// One spot per target, except JPEG fanned out: one per quality, Best to Small.
    private static func spots(for target: Offers.Target, fannedOut: Bool) -> [Spot] {
        guard fannedOut, target.format == .jpeg else {
            return [Spot(title: target.format.name, estimate: target.estimate, choices: [Choice(target)], preset: nil)]
        }
        return JPEGQuality.allCases.map { quality in
            Spot(title: quality.name, estimate: target.presets.first { $0.quality == quality }?.estimate,
                 choices: [Choice(kind: target.kind, format: .jpeg, quality: quality, files: target.files)],
                 preset: quality, isDefault: quality == target.quality)
        }
    }

    /// `count` angles `step` degrees apart, centred on `centre`.
    private static func spread(_ count: Int, around centre: Double, step: Double) -> [Double] {
        (0..<count).map { centre + (Double($0) - Double(count - 1) / 2) * step }
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
