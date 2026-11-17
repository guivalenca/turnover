import Foundation
import RingModel
import Testing
import TurnoverKit

/// Which entry the pointer highlights: each entry owns the arc halfway to its neighbours.
@Suite struct Highlight {
    @Test func eachOfTwoEntriesOwnsHalfTheCircle() {
        let ring = RingModel.opened(with: Sample.images([Sample.photo]))

        #expect(ring.entries.map(\.arc) == [.init(start: 90, end: 270), .init(start: -90, end: 90)])
    }

    @Test func aSingleEntryOwnsTheWholeCircle() {
        let ring = RingModel.opened(with: Sample.movies([Sample.movie]))

        #expect(ring.entries.map(\.arc) == [.init(start: -270, end: 90)])
    }

    @Test(arguments: [(180.0, "PNG"), (91, "PNG"), (89, "JPEG"), (0, "JPEG"), (-89, "JPEG"), (-91, "PNG")])
    func thePointerHighlightsTheEntryWhoseArcItIsIn(degrees: Double, expected: String) {
        var ring = RingModel.opened(with: Sample.images([Sample.photo]))

        ring.send(.pointer(at: degrees, distance: 100))

        #expect(ring.highlighted?.title == expected)
    }

    @Test func aSingleEntryIsHighlightedFromBelowToo() {
        var ring = RingModel.opened(with: Sample.movies([Sample.movie]))

        ring.send(.pointer(at: 90, distance: 100))

        #expect(ring.highlighted?.title == "MP4")
    }
}

extension RingModel.Event {
    /// The pointer at `degrees` (clockwise from the right, screen coordinates) and `distance`
    /// points from the centre.
    static func pointer(at degrees: Double, distance: Double) -> Self {
        let radians = degrees * .pi / 180
        return .pointer(x: distance * cos(radians), y: distance * sin(radians))
    }
}
