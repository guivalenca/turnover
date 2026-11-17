import CoreGraphics
import RingModel
import Testing

/// Where the ring goes on screen. Screen coordinates here are AppKit's: y grows upwards.
@Suite struct OnScreen {
    /// A 1728 × 1117 display with a 33 pt menu bar.
    let screen = CGRect(x: 0, y: 0, width: 1728, height: 1084)
    /// The ring's drawing around its centre: a 136 pt disc, plus the caption below it.
    let ring = CGRect(x: -136, y: -180, width: 272, height: 316)

    @Test func aRingOpenedAwayFromTheEdgesIsCentredOnThePointer() {
        let centre = RingGeometry.centre(openingAt: CGPoint(x: 800, y: 500), drawing: ring, within: screen)

        #expect(centre == CGPoint(x: 800, y: 500))
    }

    @Test func nearTheLeftEdgeTheRingMovesRightUntilItIsFullyOnScreen() {
        let centre = RingGeometry.centre(openingAt: CGPoint(x: 20, y: 500), drawing: ring, within: screen)

        #expect(centre == CGPoint(x: 136, y: 500))
    }

    @Test func inTheBottomRightCornerItMovesUpAndLeftKeepingTheCaptionOnScreen() {
        let centre = RingGeometry.centre(openingAt: CGPoint(x: 1720, y: 10), drawing: ring, within: screen)

        #expect(centre == CGPoint(x: 1592, y: 180))
    }
}

/// Which way the highlight turns to reach an entry. Angles are the model's: degrees clockwise
/// from the right; the highlight's own angle keeps counting past a full turn.
@Suite struct HighlightTurn {
    @Test func itTurnsTheShorterWayAcrossTheLeft() {
        #expect(RingGeometry.turn(to: -170, from: 170) == 190)
    }

    /// PNG on the left, JPEG on the right: half a turn apart either way.
    @Test func halfATurnAwayItGoesTheWayThePointerWent() {
        #expect(RingGeometry.turn(to: 0, from: 180, passing: -90) == 360)
        #expect(RingGeometry.turn(to: 0, from: 180, passing: 90) == 0)
        #expect(RingGeometry.turn(to: 180, from: 360, passing: 90) == 540)
        #expect(RingGeometry.turn(to: 180, from: 360, passing: -90) == 180)
    }
}

/// The dragged file's icon over the ring: smaller, and still where the pointer holds it.
@Suite struct DragImage {
    @Test func anIconViewIconShrinksAroundThePointer() {
        let icon = CGRect(x: 100, y: 200, width: 64, height: 64)
        let shrunk = RingGeometry.shrink(icon, toward: CGPoint(x: 116, y: 216), side: 32)

        // The pointer held it a quarter of the way in; it still does.
        #expect(shrunk == CGRect(x: 108, y: 208, width: 32, height: 32))
    }

    @Test func aSmallListViewIconKeepsItsSizeAndComesUpToThePointer() {
        // Finder's list view: a 16 pt icon, held by its name 120 pt to the right.
        let icon = CGRect(x: 100, y: 200, width: 16, height: 16)
        let shrunk = RingGeometry.shrink(icon, toward: CGPoint(x: 236, y: 208), side: 32)

        #expect(shrunk == CGRect(x: 220, y: 200, width: 16, height: 16))
    }
}

/// How wide an entry's label can be: inside the glass band, and clear of its neighbours.
@Suite struct LabelRoom {
    /// The drawn ring: labels at radius 87, text kept between 51 and 122 from the centre.
    let band: ClosedRange<CGFloat> = 51...122

    @Test func aLabelBesideTheHubIsAsWideAsTheBandAllows() {
        // JPEG on the right of a two-entry ring: its outer corners touch the band's edge.
        let width = RingGeometry.labelWidth(at: 0, spacing: 180, height: 30, radius: 87, band: band)

        #expect(abs(width - 68.1) < 0.1)
    }

    @Test func aFannedOutLabelStaysClearOfItsNeighbours() {
        // High, at the top, with Best and Small 54° either side.
        let width = RingGeometry.labelWidth(at: -90, spacing: 54, height: 30, radius: 87, band: band)

        #expect(abs(width - 71.0) < 0.1)
    }
}
