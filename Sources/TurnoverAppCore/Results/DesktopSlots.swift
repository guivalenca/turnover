import Foundation

/// Where new files go on the Desktop after a ring drop: the first at the drop point, the next
/// ones in a row to its right, wrapping onto a new row below at the screen's edge. Finder snaps
/// each one to its grid when it has "Snap to Grid" on.
///
/// Points are Finder desktop positions: icon centres, top-left origin.
public struct DesktopSlots: Sendable, Equatable {
    /// The first slot.
    public let drop: CGPoint
    /// The distance between neighbouring slots: one grid cell or a little more, so that two
    /// files never snap to the same cell.
    public let pitch: CGSize
    /// The visible frame of the screen the drop was on, in top-left-origin points.
    public let screen: CGRect
    /// How many slots have been handed out.
    public private(set) var count = 0

    public init(drop: CGPoint, pitch: CGSize, screen: CGRect) {
        self.drop = drop
        self.pitch = pitch
        self.screen = screen
    }

    /// The pitch for Finder's Desktop settings: icon size, grid spacing and label text size.
    /// A label takes two lines of text below the icon.
    public static func pitch(iconSize: Double, gridSpacing: Double, textSize: Double) -> CGSize {
        CGSize(width: iconSize + gridSpacing, height: iconSize + gridSpacing + 2 * textSize)
    }

    /// The next slot. Every slot stays at least half a pitch inside the screen.
    public mutating func next() -> CGPoint {
        let inside = screen.insetBy(dx: pitch.width / 2, dy: pitch.height / 2)
        let start = clamp(drop, to: inside)
        let columns = max(1, Int(((inside.maxX - start.x) / pitch.width).rounded(.down)) + 1)
        let slot = CGPoint(
            x: start.x + CGFloat(count % columns) * pitch.width,
            y: start.y + CGFloat(count / columns) * pitch.height)
        count += 1
        return clamp(slot, to: inside)
    }

    private func clamp(_ point: CGPoint, to rect: CGRect) -> CGPoint {
        guard !rect.isNull, rect.width >= 0, rect.height >= 0 else { return point }
        return CGPoint(x: min(max(point.x, rect.minX), rect.maxX), y: min(max(point.y, rect.minY), rect.maxY))
    }
}
