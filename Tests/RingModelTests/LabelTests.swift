import Foundation
import RingModel
import Testing
import TurnoverKit

/// What the entries and the hub say.
@Suite struct Labels {
    @Test func eachEntryShowsItsEstimate() {
        let ring = RingModel.opened(with: Sample.images([Sample.photo], png: .exactSize(19_000_000), jpeg: .size(3_400_000)))

        #expect(ring.entries.map(\.subtitle) == ["19 MB", "~3.4 MB"])
    }

    @Test func anEntryNotEstimatedYetShowsAnEllipsis() {
        let ring = RingModel.opened(with: Sample.movies([Sample.movie]))

        #expect(ring.entries.map(\.subtitle) == ["…"])
    }

    @Test func newerEstimatesUpdateTheEntriesAndKeepTheHighlight() {
        var ring = RingModel.opened(with: Sample.images([Sample.photo], png: .size(20_000_000)))
        ring.send(.pointer(at: 180, distance: 90))

        ring.send(.offers(Sample.images([Sample.photo], png: .exactSize(19_000_000))))

        #expect(ring.entries.first?.subtitle == "19 MB")
        #expect(ring.highlighted?.title == "PNG")
    }

    @Test func theHubPreviewsASingleImageTargetWithItsSize() {
        var ring = RingModel.opened(with: Sample.images([Sample.photo], png: .exactSize(19_000_000)))

        ring.send(.pointer(at: 180, distance: 90))

        #expect(ring.hub?.text == "PNG · 19 MB")
        #expect(ring.hub?.title == "PNG")
        #expect(ring.hub?.detail == "19 MB")
    }

    @Test func theHubPreviewsMP4WithItsTime() {
        var ring = RingModel.opened(with: Sample.movies([Sample.movie], mp4: .instant))

        ring.send(.pointer(at: -90, distance: 90))

        #expect(ring.hub?.text == "MP4 · Instant")
    }

    @Test func theHubCountsTheFilesBeforeTheirSizeIsKnown() {
        var ring = RingModel.opened(with: Sample.images([Sample.photo, Sample.photo2]))

        ring.send(.pointer(at: 180, distance: 90))

        #expect(ring.hub?.text == "PNG · 2 images")
    }

    @Test(arguments: [
        (Sample.images([Sample.photo, Sample.photo2]), "2", "images"),
        (Sample.movies([Sample.movie]), "1", "video"),
    ])
    func withNothingHighlightedTheHubCountsTheFiles(offers: Offers, title: String, detail: String) {
        let ring = RingModel.opened(with: offers)

        #expect(ring.hub?.title == title)
        #expect(ring.hub?.detail == detail)
        #expect(ring.hub?.text == "\(title) \(detail)")
    }

    @Test func theHubIsEmptyUntilTheFilesAreKnown() {
        var ring = RingModel()
        ring.send(.dragStarted(shiftDown: false))

        ring.send(.shift(down: true))

        #expect(ring.hub == nil)
    }
}
