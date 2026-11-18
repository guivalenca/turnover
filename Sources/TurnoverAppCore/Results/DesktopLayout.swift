import Foundation

/// Where new files go on the Desktop when the ring was dropped there (#18).
///
/// With Snap to Grid, each file takes the free grid spot nearest the drop. Finder doesn't snap
/// an icon that is moved over Apple Events, so the grid is worked out here, from the icons
/// already on the Desktop: their positions repeat at the grid's spacing. Without a grid, the
/// first file goes exactly where the ring was dropped and the next ones in a row to its right.
/// A Desktop that Finder keeps sorted is left to Finder.
///
/// Points are Finder `desktop position`s: global points from the top left of the main screen.
/// Reading an icon's position and moving an icon use the same ones, so a grid read from the
/// icons is the grid a new icon is moved onto.
public struct DesktopLayout: Sendable, Equatable {
    /// How Finder arranges the Desktop: View › Sort By.
    public enum Arrangement: Sendable, Equatable {
        /// None: icons stay where they are put.
        case free
        /// Snap to Grid.
        case grid
        /// By name, kind, date and so on: Finder places every icon itself.
        case keptArranged

        /// From `arrangeBy` in Finder's `DesktopViewSettings`.
        public init(finderSetting: String?) {
            switch finderSetting {
            case "grid": self = .grid
            case nil, "none": self = .free
            default: self = .keptArranged
            }
        }
    }

    public var arrangement: Arrangement
    /// The visible frame of the screen the ring was dropped on, in the same points.
    public var screen: CGRect
    /// Finder's Desktop icon size.
    public var iconSize: CGFloat
    /// Finder's Desktop label text size.
    public var textSize: CGFloat

    public init(arrangement: Arrangement, screen: CGRect, iconSize: CGFloat, textSize: CGFloat) {
        self.arrangement = arrangement
        self.screen = screen
        self.iconSize = iconSize
        self.textSize = textSize
    }

    /// The grid's spacing when the icons on the Desktop don't show it. Measured on macOS 27
    /// with 64-point icons and 12-point labels: 128 by 112. Finder doesn't document how its
    /// grid spacing setting maps to points, so the icons are trusted first.
    public var expectedPitch: CGSize {
        CGSize(width: 2 * iconSize, height: iconSize + 4 * textSize)
    }

    /// Where to put `count` new files, for a ring dropped at `drop`, given where the other
    /// icons on the Desktop are. Empty when Finder keeps the Desktop arranged.
    public func places(for count: Int, droppedAt drop: CGPoint, icons: [CGPoint]) -> [CGPoint] {
        switch arrangement {
        case .keptArranged:
            return []
        case .free:
            return row(of: count, from: drop)
        case .grid:
            guard let grid = Grid(icons: icons.filter(isNearScreen), expected: expectedPitch) else {
                return row(of: count, from: drop)
            }
            return nearestFree(count, on: grid, to: drop, icons: icons)
        }
    }

    // MARK: Snap to Grid

    /// Grid spots inside the screen, nearest to `drop` first, without an icon, the first
    /// `count` of them. On a tie, below before above and right before left.
    private func nearestFree(_ count: Int, on grid: Grid, to drop: CGPoint, icons: [CGPoint]) -> [CGPoint] {
        let area = CGRect(
            x: screen.minX + iconSize / 2, y: screen.minY + iconSize / 2,
            width: screen.width - iconSize, height: screen.height - iconSize - 2 * textSize)
        let free = grid.points(in: area).filter { spot in
            !icons.contains { abs($0.x - spot.x) < grid.pitch.width * 0.75 && abs($0.y - spot.y) < grid.pitch.height * 0.75 }
        }
        func key(_ spot: CGPoint) -> (CGFloat, Int, Int) {
            let distance = ((spot.x - drop.x) * (spot.x - drop.x) + (spot.y - drop.y) * (spot.y - drop.y)).squareRoot()
            return ((distance * 100).rounded(), spot.y < drop.y ? 1 : 0, spot.x < drop.x ? 1 : 0)
        }
        let nearest = free.sorted { key($0) < key($1) }.prefix(count)
        return Array(nearest) + Array(repeating: drop, count: count - nearest.count)
    }

    private func isNearScreen(_ icon: CGPoint) -> Bool {
        screen.insetBy(dx: -iconSize, dy: -iconSize).contains(icon)
    }

    /// Finder's Desktop grid: lines a pitch apart, through one icon on it.
    struct Grid: Equatable {
        var origin: CGPoint
        var pitch: CGSize

        /// The grid most of `icons` sit on, or nil without icons.
        init?(icons: [CGPoint], expected: CGSize) {
            guard let x = Self.lines(icons.map(\.x), expected: expected.width),
                  let y = Self.lines(icons.map(\.y), expected: expected.height)
            else { return nil }
            origin = CGPoint(x: x.offset, y: y.offset)
            pitch = CGSize(width: x.pitch, height: y.pitch)
        }

        /// Its points inside `area`.
        func points(in area: CGRect) -> [CGPoint] {
            func steps(_ offset: CGFloat, _ pitch: CGFloat, _ low: CGFloat, _ high: CGFloat) -> [CGFloat] {
                guard pitch > 0, low <= high else { return [] }
                let first = offset + ((low - offset) / pitch).rounded(.up) * pitch
                return Array(stride(from: first, through: high, by: pitch))
            }
            let xs = steps(origin.x, pitch.width, area.minX, area.maxX)
            let ys = steps(origin.y, pitch.height, area.minY, area.maxY)
            return ys.flatMap { y in xs.map { CGPoint(x: $0, y: y) } }
        }

        /// Icons within this many points of a grid line are on it.
        static let tolerance: CGFloat = 3

        /// The spacing and one position of the grid lines along one axis, from the icons'
        /// coordinates on it: the spacing that puts the most icons on lines, from the gaps
        /// between neighbouring lines and their fractions near `expected`. On a tie, the one
        /// nearest `expected`.
        static func lines(_ values: [CGFloat], expected: CGFloat) -> (pitch: CGFloat, offset: CGFloat)? {
            var lines: [CGFloat] = []
            for value in values.sorted() where lines.last.map({ value - $0 > tolerance }) ?? true {
                lines.append(value)
            }
            guard !lines.isEmpty else { return nil }
            let range = (expected * 0.6)...(expected * 1.6)
            var candidates: Set<CGFloat> = [expected]
            for (low, high) in zip(lines, lines.dropFirst()) {
                let gap = high - low
                for parts in 1...max(1, Int(gap / range.lowerBound)) where range.contains(gap / CGFloat(parts)) {
                    candidates.insert(((gap / CGFloat(parts)) * 4).rounded() / 4)
                }
            }
            var best: (pitch: CGFloat, offset: CGFloat, fit: Int)?
            for pitch in candidates.sorted() {
                for offset in lines {
                    let fit = values.count(where: { value in
                        let rest = (value - offset).truncatingRemainder(dividingBy: pitch)
                        return min(abs(rest), pitch - abs(rest)) <= tolerance
                    })
                    if let current = best,
                       fit < current.fit || (fit == current.fit && abs(pitch - expected) >= abs(current.pitch - expected)) {
                        continue
                    }
                    best = (pitch, offset, fit)
                }
            }
            return best.map { ($0.pitch, $0.offset) }
        }
    }

    // MARK: No grid

    /// The drop point, then a row to its right a cell apart, wrapping onto a new row below at
    /// the screen's edge. Every point stays at least half a cell inside the screen.
    private func row(of count: Int, from drop: CGPoint) -> [CGPoint] {
        let pitch = expectedPitch
        let inside = screen.insetBy(dx: pitch.width / 2, dy: pitch.height / 2)
        let start = clamp(drop, to: inside)
        let columns = max(1, Int(((inside.maxX - start.x) / pitch.width).rounded(.down)) + 1)
        return (0..<count).map { index in
            clamp(CGPoint(
                x: start.x + CGFloat(index % columns) * pitch.width,
                y: start.y + CGFloat(index / columns) * pitch.height), to: inside)
        }
    }

    private func clamp(_ point: CGPoint, to rect: CGRect) -> CGPoint {
        guard !rect.isNull, rect.width >= 0, rect.height >= 0 else { return point }
        return CGPoint(x: min(max(point.x, rect.minX), rect.maxX), y: min(max(point.y, rect.minY), rect.maxY))
    }
}
