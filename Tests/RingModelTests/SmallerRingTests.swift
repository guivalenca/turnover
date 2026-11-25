import Foundation
import RingModel
import Testing
import TurnoverKit

/// MP4s on the ring: making them smaller, at a quality.
@Suite struct SmallerRing {
    @Test func anMP4AloneOpensWithItsQualitiesAndSizes() {
        let ring = RingModel.opened(with: Sample.mp4s([Sample.mp4], presets: [.high: 31_000_000, .medium: 12_000_000, .small: 4_000_000]))

        #expect(ring.entries.map(\.title) == ["High", "Medium", "Small"])
        #expect(ring.entries.map(\.subtitle) == ["~31 MB", "~12 MB", "~4.0 MB"])
        #expect(ring.entries.map(\.angle) == [150, -90, 30])
        #expect(ring.entries.map(\.isDefault) == [false, true, false])
        #expect(ring.hub?.text == "Smaller · 1 video")
    }

    @Test func optionChangesNothingThere() {
        var ring = RingModel.opened(with: Sample.mp4s([Sample.mp4]))
        let before = ring.entries

        ring.send(.option(down: true))

        #expect(ring.entries == before)
        #expect(ring.hub?.text == "Smaller · 1 video")
    }

    @Test(arguments: [(150.0, VideoQuality.high), (-90, .medium), (30, .small)])
    func aDropConvertsAtTheQuality(degrees: Double, quality: VideoQuality) {
        var ring = RingModel.opened(with: Sample.mp4s([Sample.mp4], presets: [quality: 12_000_000]))
        ring.send(.pointer(at: degrees, distance: 90))

        #expect(ring.hub?.text == "\(quality.name) · ~12 MB")
        ring.send(.drop)

        #expect(ring.outcome == .convert([.init(kind: .video, format: .smaller, quality: .video(quality), files: [Sample.mp4])]))
    }

    @Test func nextToAMovieItIsOneEntryThatOptionFansOut() {
        let offers = Offers(groups: [.init(kind: .video, files: [Sample.movie, Sample.mp4], targets:
            Sample.movies([Sample.movie]).targets + Sample.mp4s([Sample.mp4]).targets)])
        var ring = RingModel.opened(with: offers)
        #expect(ring.entries.map(\.title) == ["MP4", "Smaller"])
        #expect(ring.entries.map(\.angle) == [180, 0])

        ring.send(.option(down: true))

        #expect(ring.entries.map(\.title) == ["MP4", "High", "Medium", "Small"])
        #expect(ring.entries.map(\.angle) == [180, -54, 0, 54])
        #expect(ring.hub?.text == "Smaller · 1 video")
    }

    @Test func nextToPhotosItIsAddedAtTheDefaultQuality() {
        var ring = RingModel.opened(with: Offers(groups: Sample.images([Sample.photo]).groups + Sample.mp4s([Sample.mp4]).groups))
        #expect(ring.entries.map(\.title) == ["PNG", "JPEG", "Smaller"])
        ring.send(.time(0))
        ring.send(.pointer(at: 0, distance: 90))
        ring.send(.time(1))
        #expect(ring.caption == "Smaller added · drop to convert")
        ring.send(.pointer(at: 143, distance: 90))

        #expect(ring.hub?.text == "Smaller + PNG · 2 files")
        ring.send(.drop)

        #expect(ring.outcome == .convert([
            .init(kind: .video, format: .smaller, quality: .video(.medium), files: [Sample.mp4]),
            .init(kind: .image, format: .png, files: [Sample.photo]),
        ]))
    }

    @Test func aQualityAddedIsNamedInTheCaption() {
        var ring = RingModel.opened(with: Offers(groups: Sample.images([Sample.photo]).groups + Sample.mp4s([Sample.mp4]).groups))
        ring.send(.option(down: true))
        #expect(ring.entries.map(\.angle) == [102, 154, -154, -102, -52, 0, 52])
        ring.send(.time(0))
        ring.send(.pointer(at: 0, distance: 90))
        ring.send(.time(1))

        #expect(ring.caption == "Smaller (Medium) added · drop to convert")
    }

    @Test func everythingFannedOutAtOnceIsEvenlySpread() {
        let videos = Offers.Group(kind: .video, files: [Sample.movie, Sample.mp4], targets:
            Sample.movies([Sample.movie]).targets + Sample.mp4s([Sample.mp4]).targets)
        var ring = RingModel.opened(with: Offers(groups: Sample.images([Sample.photo]).groups + [videos]))

        ring.send(.option(down: true))

        #expect(ring.entries.map(\.title) == ["PNG", "Best", "High", "Small", "MP4", "High", "Medium", "Small"])
        #expect(Set(ring.entries.map { $0.arc.end - $0.arc.start }) == [45])
        #expect(ring.hub?.text == "3 files")
    }
}
