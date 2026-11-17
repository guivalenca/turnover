import Foundation
import RingModel
import Testing
import TurnoverKit

/// Where the entries sit. Angles are in degrees, clockwise from the right: -90° is the top.
@Suite struct Layout {
    @Test func aSingleEntrySitsAtTheTop() {
        let ring = RingModel.opened(with: Sample.movies([Sample.movie]))

        #expect(ring.entries.map(\.title) == ["MP4"])
        #expect(ring.entries.map(\.angle) == [-90])
    }

    @Test func twoEntriesSitLeftAndRightWithPNGOnTheLeft() {
        let ring = RingModel.opened(with: Sample.images([Sample.photo]))

        #expect(ring.entries.map(\.title) == ["PNG", "JPEG"])
        #expect(ring.entries.map(\.angle) == [180, 0])
    }
}
