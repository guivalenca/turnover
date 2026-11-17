import Foundation
import RingModel
import Testing
import TurnoverKit

/// ⌥ fans JPEG out into its three qualities, for one drop.
@Suite struct FanOut {
    @Test func optionFansJPEGOutIntoItsQualities54DegreesApartAroundJPEG() {
        var ring = RingModel.opened(with: Sample.images([Sample.photo]))

        ring.send(.option(down: true))

        #expect(ring.entries.map(\.title) == ["PNG", "Best", "High", "Small"])
        #expect(ring.entries.map(\.angle) == [180, -54, 0, 54])
    }

    @Test func theQualitiesShowTheirEstimatesAndMarkTheDefault() {
        var ring = RingModel.opened(with: Sample.images([Sample.photo], jpegQuality: .small, presets: [
            .best: .exactSize(5_200_000), .high: .size(2_100_000), .small: .size(900_000),
        ]))

        ring.send(.option(down: true))

        #expect(ring.entries.map(\.subtitle) == ["…", "5.2 MB", "~2.1 MB", "~900 KB"])
        #expect(ring.entries.map(\.isDefault) == [false, false, false, true])
    }

    @Test func aQualityNotEstimatedYetShowsAnEllipsis() {
        var ring = RingModel.opened(with: Sample.images([Sample.photo], presets: [.high: .size(2_100_000)]))

        ring.send(.option(down: true))

        #expect(ring.entries.map(\.subtitle) == ["…", "…", "~2.1 MB", "…"])
    }

    @Test func releasingOptionFoldsTheQualitiesBackIntoJPEG() {
        var ring = RingModel.opened(with: Sample.images([Sample.photo]))
        ring.send(.option(down: true))

        ring.send(.option(down: false))

        #expect(ring.entries.map(\.title) == ["PNG", "JPEG"])
        #expect(ring.entries.map(\.angle) == [180, 0])
    }

    @Test func withJPEGAloneTheQualitiesFanOutAroundTheTop() {
        var ring = RingModel.opened(with: Sample.pngs([Sample.screenshot]))

        ring.send(.option(down: true))

        #expect(ring.entries.map(\.title) == ["Best", "High", "Small"])
        #expect(ring.entries.map(\.angle) == [-144, -90, -36])
    }

    @Test func optionDoesNothingWithoutJPEG() {
        var ring = RingModel.opened(with: Sample.movies([Sample.movie]))

        ring.send(.option(down: true))

        #expect(ring.entries.map(\.title) == ["MP4"])
        #expect(ring.isFannedOut == false)
    }

    @Test func optionHeldBeforeShiftOpensTheRingFannedOut() {
        var ring = RingModel()
        ring.send(.dragStarted(shiftDown: false))
        ring.send(.option(down: true))
        ring.send(.offers(Sample.images([Sample.photo])))

        ring.send(.shift(down: true))

        #expect(ring.isFannedOut)
        #expect(ring.entries.map(\.title) == ["PNG", "Best", "High", "Small"])
    }

    @Test(arguments: [(-54.0, JPEGQuality.best), (0, .high), (54, .small)])
    func aDropOnAQualityConvertsWithIt(degrees: Double, quality: JPEGQuality) {
        var ring = RingModel.opened(with: Sample.images([Sample.photo]))
        ring.send(.option(down: true))
        ring.send(.pointer(at: degrees, distance: 90))

        ring.send(.drop)

        #expect(ring.outcome == .convert([.init(kind: .image, format: .jpeg, quality: quality, files: [Sample.photo])]))
    }

    @Test func theQualityIsForThatDropOnly() {
        var ring = RingModel.opened(with: Sample.images([Sample.photo]))
        ring.send(.option(down: true))
        ring.send(.pointer(at: -54, distance: 90))
        ring.send(.drop)
        ring.send(.option(down: false))

        ring.send(.dragStarted(shiftDown: false))
        ring.send(.offers(Sample.images([Sample.photo])))
        ring.send(.shift(down: true))
        ring.send(.pointer(at: 0, distance: 90))
        ring.send(.drop)

        #expect(ring.outcome == .convert([.init(kind: .image, format: .jpeg, quality: .high, files: [Sample.photo])]))
    }

    @Test func releasingOptionOverAQualityHighlightsJPEG() {
        var ring = RingModel.opened(with: Sample.images([Sample.photo]))
        ring.send(.option(down: true))
        ring.send(.pointer(at: 54, distance: 90))

        ring.send(.option(down: false))
        ring.send(.drop)

        #expect(ring.outcome == .convert([.init(kind: .image, format: .jpeg, quality: .high, files: [Sample.photo])]))
    }

    @Test func withNothingHighlightedTheHubSaysJPEGQuality() {
        var ring = RingModel.opened(with: Sample.images([Sample.photo]))

        ring.send(.option(down: true))

        #expect(ring.hub?.title == "JPEG")
        #expect(ring.hub?.detail == "quality")
        #expect(ring.hub?.text == "JPEG quality")
    }

    @Test func theHubPreviewsAQualityWithItsSize() {
        var ring = RingModel.opened(with: Sample.images([Sample.photo], presets: [.best: .exactSize(5_200_000)]))
        ring.send(.option(down: true))

        ring.send(.pointer(at: -54, distance: 90))

        #expect(ring.hub?.title == "JPEG")
        #expect(ring.hub?.detail == "Best · 5.2 MB")
        #expect(ring.hub?.text == "JPEG · Best · 5.2 MB")
    }

    @Test func theHubCountsTheFilesForAQualityNotEstimatedYet() {
        var ring = RingModel.opened(with: Sample.images([Sample.photo, Sample.photo2]))
        ring.send(.option(down: true))

        ring.send(.pointer(at: 54, distance: 90))

        #expect(ring.hub?.text == "JPEG · Small · 2 images")
    }

    @Test func overPNGTheHubIsUnchanged() {
        var ring = RingModel.opened(with: Sample.images([Sample.photo], png: .exactSize(19_000_000)))
        ring.send(.option(down: true))

        ring.send(.pointer(at: 180, distance: 90))

        #expect(ring.hub?.text == "PNG · 19 MB")
    }
}
