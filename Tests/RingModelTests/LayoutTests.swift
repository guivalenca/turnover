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

    // A mixed drag: images on the left, centred on 180°; videos on the right, at 0°.
    // Angles past 180° read as negative: 217° is -143°.

    @Test func aMixedDragPutsImagesLeft74DegreesApartAndVideosRight() {
        let ring = RingModel.opened(with: Sample.mixed([Sample.photo], [Sample.movie]))

        #expect(ring.entries.map(\.title) == ["PNG", "JPEG", "MP4"])
        #expect(ring.entries.map(\.angle) == [143, -143, 0])
    }

    @Test func aMixedDragFannedOutPutsTheImages52DegreesApart() {
        var ring = RingModel.opened(with: Sample.mixed([Sample.photo], [Sample.movie]))

        ring.send(.option(down: true))

        #expect(ring.entries.map(\.title) == ["PNG", "Best", "High", "Small", "MP4"])
        #expect(ring.entries.map(\.angle) == [102, 154, -154, -102, 0])
    }

    @Test func aMixedDragWithJPEGAloneForImagesPutsItLeft() {
        var ring = RingModel.opened(with: Sample.mixed(pngs: [Sample.screenshot], [Sample.movie]))

        #expect(ring.entries.map(\.angle) == [180, 0])

        ring.send(.option(down: true))

        #expect(ring.entries.map(\.title) == ["Best", "High", "Small", "MP4"])
        #expect(ring.entries.map(\.angle) == [128, 180, -128, 0])
    }

    @Test(arguments: [(160.0, "PNG"), (75, "PNG"), (200, "JPEG"), (-75, "JPEG"), (60, "MP4"), (-60, "MP4")])
    func inAMixedRingEachEntryOwnsTheArcHalfwayToItsNeighbours(degrees: Double, expected: String) {
        var ring = RingModel.opened(with: Sample.mixed([Sample.photo], [Sample.movie]))

        ring.send(.pointer(at: degrees, distance: 100))

        #expect(ring.highlighted?.title == expected)
    }
}
