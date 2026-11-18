import CoreGraphics

/// Geometry for drawing the ring, with no AppKit: where it goes near a screen's edges, which way
/// the highlight turns, how much room each label has, and where the shrunk drag image goes.
/// Angles are the model's: degrees clockwise from the right, -90° at the top.
public enum RingGeometry {
    /// The ring's size, in points from its centre: the prototype's proportions. The view draws
    /// with these, and the model hit-tests with them, so a drop converts exactly where an entry
    /// is drawn.
    ///
    /// The glass disc's edge: beyond it the pointer is off the ring, and a drop cancels.
    public static let outerRadius: CGFloat = 128
    /// The hub lens's edge: inside it nothing is highlighted, and a drop cancels.
    public static let hubRadius: CGFloat = 42
    /// Where the entries' labels are centred.
    public static let labelRadius: CGFloat = 87

    /// The centre for a ring opened at `point`: the point itself, moved just enough that
    /// `drawing` (the ring's drawn bounds, relative to its centre) stays inside `frame`.
    public static func centre(openingAt point: CGPoint, drawing: CGRect, within frame: CGRect) -> CGPoint {
        CGPoint(x: clamp(point.x, frame.minX - drawing.minX, frame.maxX - drawing.maxX),
                y: clamp(point.y, frame.minY - drawing.minY, frame.maxY - drawing.maxY))
    }

    /// The angle to turn the highlight to so it shows `angle` (degrees clockwise from the right):
    /// `angle` plus or minus whole turns, the shorter way round from `current`. Half a turn away
    /// (PNG and JPEG, left and right), it goes the way through `pointer`, the pointer's angle:
    /// over the top if the pointer crossed there.
    public static func turn(to angle: Double, from current: Double, passing pointer: Double? = nil) -> Double {
        var offset = signedOffset(angle - current)
        if abs(abs(offset) - 180) < 0.001, let pointer {
            offset = signedOffset(pointer - current) < 0 ? -180 : 180
        }
        return current + offset
    }

    /// The dragged file's icon, `frame`, shrunk so its longer side is at most `side`, around
    /// `pointer`: the pointer keeps holding it at the same spot. An icon the pointer isn't on
    /// (Finder's list view holds it by the name beside it) comes up to the pointer.
    public static func shrink(_ frame: CGRect, toward pointer: CGPoint, side: CGFloat) -> CGRect {
        let scale = min(1, side / max(frame.width, frame.height))
        var shrunk = CGRect(x: pointer.x + (frame.minX - pointer.x) * scale, y: pointer.y + (frame.minY - pointer.y) * scale,
                            width: frame.width * scale, height: frame.height * scale)
        shrunk.origin.x = clamp(shrunk.minX, pointer.x - shrunk.width, pointer.x)
        shrunk.origin.y = clamp(shrunk.minY, pointer.y - shrunk.height, pointer.y)
        return shrunk
    }

    /// The widest a label `height` tall can be, centred `radius` from the ring's centre at
    /// `angle`: its corners stay within `band` (distances from the centre), and it stays a gap
    /// clear of the labels `spacing` degrees either side (nil: it has no neighbours).
    public static func labelWidth(at angle: Double, spacing: Double?, height: CGFloat, radius: CGFloat,
                                  band: ClosedRange<CGFloat>) -> CGFloat {
        let x = abs(radius * cos(angle * .pi / 180)), y = abs(radius * sin(angle * .pi / 180))
        // The corner farthest from the centre stays inside the outer edge.
        var half = (band.upperBound * band.upperBound - (y + height / 2) * (y + height / 2)).squareRoot() - x
        // The point nearest the centre stays outside the inner edge (the hub).
        let below = max(0, y - height / 2)
        if below < band.lowerBound {
            half = min(half, x - (band.lowerBound * band.lowerBound - below * below).squareRoot())
        }
        var width = 2 * half
        if let spacing, spacing < 180 {
            width = min(width, 2 * radius * sin(spacing / 2 * .pi / 180) - labelGap)
        }
        return max(0, width)
    }

    /// The least room between two entries' labels.
    private static let labelGap: CGFloat = 8

    /// `degrees` as the shortest turn: in -180...180.
    private static func signedOffset(_ degrees: Double) -> Double {
        let offset = degrees.truncatingRemainder(dividingBy: 360)
        return offset > 180 ? offset - 360 : offset < -180 ? offset + 360 : offset
    }

    private static func clamp(_ value: CGFloat, _ lowest: CGFloat, _ highest: CGFloat) -> CGFloat {
        min(max(value, lowest), highest)
    }
}
