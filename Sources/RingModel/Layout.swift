import TurnoverKit

extension RingModel {
    /// One format on the ring.
    public struct Entry: Sendable, Hashable {
        /// The format ("PNG", "JPEG", "MP4", "Smaller"), a quality fanned out ("Best", "High",
        /// "Medium", "Small"), or "Original" for an image dragged out of a web page, saved as it is.
        public let title: String
        /// Its estimate: "19 MB" (measured), "~19 MB", "Instant", "About 5 s"; "…" until known.
        /// Original names the image's own format first: "WebP · 212 KB".
        public var subtitle: String {
            let label = estimate?.label ?? "…"
            return note.map { RingModel.line($0, label) } ?? label
        }
        /// What the subtitle says before the estimate: the image's own format, for Original.
        public let note: String?
        /// For every file it converts together; nil until estimated.
        public let estimate: Estimate?
        /// Where it sits, in degrees clockwise from the right (screen coordinates, y down):
        /// -90° is the top, 180° the left.
        public let angle: Double
        /// The angles it owns, halfway to each neighbour: the pointer anywhere in it highlights it.
        public let arc: Arc
        /// What a drop on it converts.
        public let choices: [Choice]
        /// The quality it stands for when its format is fanned out ("Best", say); nil for a format.
        public let quality: Quality?
        /// A fanned out quality that is the default: it is marked.
        public let isDefault: Bool
        /// Added by resting on it: it stays tinted, with a ✓.
        public let isAdded: Bool

        /// Which format, or quality, of which kind of file it is, whatever its estimate.
        public var id: ID { ID(kind: choices[0].kind, format: choices[0].format, quality: quality) }

        public struct ID: Sendable, Hashable {
            public let kind: SourceFile.Kind
            public let format: OutputFormat
            /// Set for a fanned out quality; nil for the format itself.
            public let quality: Quality?
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

        /// The arc an entry at `angle` owns among entries at `angles` (its own included): halfway
        /// to the nearest entry on each side, or the whole circle for a lone entry.
        public init(around angle: Double, among angles: [Double]) {
            let others = angles.filter { $0 != angle }
            guard !others.isEmpty else {
                self.init(start: angle - 180, end: angle + 180)
                return
            }
            // How far clockwise each other entry is, in (0, 360).
            let clockwise = others.map { other in
                let d = (other - angle).truncatingRemainder(dividingBy: 360)
                return d <= 0 ? d + 360 : d
            }
            let next = clockwise.min()!, previous = 360 - clockwise.max()!
            self.init(start: angle - previous / 2, end: angle + next / 2)
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
    /// where JPEG was: 54° apart, or 52° in a mixed ring. A smaller MP4's do the same, and when it is
    /// all the ring offers they are there from the start, a
    /// third of the ring each, the middle one at the top. With both fanned out next to PNG and
    /// MP4, everything sits 45° apart. Angles are in (-180, 180].
    ///
    /// With Original (an image dragged out of a web page): Original sits at the bottom and the
    /// formats above it, a single one at the top, PNG and JPEG up left and up right (-150° and
    /// -30°), a third of the ring each.
    static func layout(_ offers: Offers, fannedOut: Bool, added: [Choice]) -> [Entry] {
        // No local is named `spots`: the runner's older Swift reports a circular reference when
        // one shadows `spots(for:fannedOut:)` in the same function.
        let groups: [(kind: SourceFile.Kind, spots: [Spot])] = offers.groups.map { group in
            (kind: group.kind, spots: group.targets.flatMap { Self.spots(for: $0, fannedOut: fannedOut) })
        }
        let angles: [Double]
        if groups.count == 1, groups[0].spots.contains(where: \.isOriginal) {
            let formats = groups[0].spots.filter { !$0.isOriginal }
            let above: [Double]
            if formats.contains(where: { $0.preset != nil }) {
                // JPEG's qualities around where JPEG was: up right, or the top if JPEG was alone.
                above = formats.count == 3 ? spread(3, around: -90, step: 54) : [-150] + spread(3, around: -30, step: 54)
            } else {
                above = formats.count == 1 ? [-90] : [-150, -30]
            }
            angles = above + [90]
        } else if groups.count == 1 {
            let only = groups[0].spots
            if only.allSatisfy({ $0.choices[0].format == .smaller && $0.preset != nil }) {
                angles = spread(only.count, around: -90, step: 360 / Double(only.count))
            } else if only.contains(where: { $0.preset != nil }) {
                // The qualities around where their format was: the right, or the top if it was alone.
                let others = only.filter { $0.preset == nil }.count
                angles = others == 1 ? [180] + spread(3, around: 0, step: 54) : spread(3, around: -90, step: 54)
            } else {
                angles = only.count == 1 ? [-90] : [180, 0]
            }
        } else {
            let total = groups.map(\.spots.count).reduce(0, +)
            angles = groups.flatMap { group -> [Double] in
                spread(group.spots.count, around: group.kind == SourceFile.Kind.video ? 0 : 180,
                       step: !fannedOut ? 74 : total > 7 ? 45 : 52)
            }
        }
        let all = groups.flatMap { $0.spots }
        let placed = angles.map(normalized)
        return zip(all, placed).map { spot, angle in
            Entry(title: spot.title, note: spot.isOriginal ? offers.original?.typeName : nil, estimate: spot.estimate,
                  angle: angle, arc: Arc(around: angle, among: placed), choices: spot.choices,
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
        /// The quality it stands for, when its format is fanned out.
        let preset: Quality?
        var isDefault = false
        /// Original: the image saved as it is.
        var isOriginal: Bool { choices[0].format == .original }
    }

    /// One spot per target, except one fanned out: one per quality, largest to smallest.
    private static func spots(for target: Offers.Target, fannedOut: Bool) -> [Spot] {
        let qualities = target.format.qualities
        guard fannedOut, !qualities.isEmpty else {
            return [Spot(title: target.format.shortName, estimate: target.estimate, choices: [Choice(target)], preset: nil)]
        }
        return qualities.map { quality in
            Spot(title: quality.name, estimate: target.presets.first { $0.quality == quality }?.estimate,
                 choices: [Choice(kind: target.kind, format: target.format, quality: quality, files: target.files)],
                 preset: quality, isDefault: quality == target.quality)
        }
    }

    /// `count` angles `step` degrees apart, centred on `centre`.
    private static func spread(_ count: Int, around centre: Double, step: Double) -> [Double] {
        (0..<count).map { centre + (Double($0) - Double(count - 1) / 2) * step }
    }

}
