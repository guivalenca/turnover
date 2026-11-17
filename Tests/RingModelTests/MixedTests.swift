import Foundation
import RingModel
import Testing
import TurnoverKit

/// Images and videos dragged together: one ring with formats for both. Resting on a format adds
/// it; a drop converts what was added plus the format dropped on.
@Suite struct Mixed {
    @Test func aDropStraightOnMP4ConvertsOnlyTheVideos() {
        var ring = RingModel.opened(with: Sample.mixed([Sample.photo], [Sample.movie]))
        ring.send(.pointer(at: 0, distance: 90))

        ring.send(.drop)

        #expect(ring.outcome == .convert([.init(kind: .video, format: .mp4, files: [Sample.movie])]))
    }

    @Test func aDropStraightOnPNGConvertsOnlyTheImages() {
        var ring = RingModel.opened(with: Sample.mixed([Sample.photo], [Sample.movie]))
        ring.send(.pointer(at: 143, distance: 90))

        ring.send(.drop)

        #expect(ring.outcome == .convert([.init(kind: .image, format: .png, files: [Sample.photo])]))
    }

    @Test func theCaptionExplainsRestToAdd() {
        let ring = RingModel.opened(with: Sample.mixed([Sample.photo], [Sample.movie]))

        #expect(ring.caption == "Rest on a format to add it, then drop on another")
    }

    @Test(arguments: [Sample.images([Sample.photo]), Sample.movies([Sample.movie])])
    func aRingForOneKindOfFileHasNoCaption(offers: Offers) {
        let ring = RingModel.opened(with: offers)

        #expect(ring.caption == nil)
    }

    @Test func withNothingHighlightedTheHubCountsAllTheFiles() {
        let ring = RingModel.opened(with: Sample.mixed([Sample.photo, Sample.photo2], [Sample.movie]))

        #expect(ring.hub?.text == "3 files")
    }

    // Rest to add. The clock is in seconds; the rest delay is the system's spring-loading delay.

    @Test func restingOnAFormatForTheDelayAddsIt() {
        var ring = RingModel.opened(with: Sample.mixed([Sample.photo], [Sample.movie]), restDelay: 0.5)
        ring.send(.time(10))
        ring.send(.pointer(at: 143, distance: 90))

        ring.send(.time(10.5))

        #expect(ring.added == [.init(kind: .image, format: .png, files: [Sample.photo])])
        #expect(ring.entries.map(\.isAdded) == [true, false, false])
    }

    @Test func restingOnPNGThenDroppingOnMP4ConvertsImagesToPNGAndVideosToMP4() {
        var ring = RingModel.opened(with: Sample.mixed([Sample.photo], [Sample.movie]), restDelay: 0.5)
        ring.send(.time(10))
        ring.send(.pointer(at: 143, distance: 90))
        ring.send(.time(10.5))
        ring.send(.time(10.7))
        ring.send(.pointer(at: 0, distance: 90))

        ring.send(.drop)

        #expect(ring.outcome == .convert([
            .init(kind: .image, format: .png, files: [Sample.photo]),
            .init(kind: .video, format: .mp4, files: [Sample.movie]),
        ]))
    }

    @Test func afterAddingPNGTheCaptionSaysSo() {
        var ring = RingModel.opened(with: Sample.mixed([Sample.photo], [Sample.movie]), restDelay: 0.5)

        ring.rest(at: 143, from: 10)

        #expect(ring.caption == "PNG added · drop to convert")
    }

    @Test func overMP4AfterAddingPNGTheHubPreviewsBothWithTheFileCount() {
        var ring = RingModel.opened(with: Sample.mixed([Sample.photo, Sample.photo2], [Sample.movie],
                                                       png: .exactSize(19_000_000), mp4: .instant))
        ring.rest(at: 143, from: 10)

        ring.send(.pointer(at: 0, distance: 90))

        #expect(ring.hub?.title == "PNG + MP4")
        #expect(ring.hub?.detail == "3 files")
        #expect(ring.hub?.text == "PNG + MP4 · 3 files")
    }

    @Test func overTheAddedFormatTheHubPreviewsItAlone() {
        var ring = RingModel.opened(with: Sample.mixed([Sample.photo], [Sample.movie], png: .exactSize(19_000_000)))

        ring.rest(at: 143, from: 10)

        #expect(ring.hub?.text == "PNG · 19 MB")
    }

    @Test func justBeforeTheDelayNothingIsAddedYet() {
        var ring = RingModel.opened(with: Sample.mixed([Sample.photo], [Sample.movie]), restDelay: 0.5)
        ring.send(.time(10))
        ring.send(.pointer(at: 143, distance: 90))

        ring.send(.time(10.49))

        #expect(ring.added.isEmpty)
        #expect(ring.rest?.entry == ring.highlighted?.id)
        #expect(ring.rest?.since == 10)
        #expect(ring.rest?.deadline == 10.5)
    }

    @Test func movingToAnotherFormatStartsTheRestAgain() {
        var ring = RingModel.opened(with: Sample.mixed([Sample.photo], [Sample.movie]), restDelay: 0.5)
        ring.send(.time(10))
        ring.send(.pointer(at: 143, distance: 90))
        ring.send(.time(10.3))
        ring.send(.pointer(at: -143, distance: 90))

        ring.send(.time(10.6))
        #expect(ring.added.isEmpty)

        ring.send(.time(10.8))
        #expect(ring.added == [.init(kind: .image, format: .jpeg, quality: .high, files: [Sample.photo])])
    }

    @Test func movingWithinTheSameFormatKeepsResting() {
        var ring = RingModel.opened(with: Sample.mixed([Sample.photo], [Sample.movie]), restDelay: 0.5)
        ring.send(.time(10))
        ring.send(.pointer(at: 143, distance: 90))
        ring.send(.time(10.3))
        ring.send(.pointer(at: 150, distance: 120))

        ring.send(.time(10.5))

        #expect(ring.added.map(\.format) == [.png])
    }

    @Test(arguments: [20.0, 300])
    func leavingForTheHubOrOffTheRingEndsTheRest(distance: Double) {
        var ring = RingModel.opened(with: Sample.mixed([Sample.photo], [Sample.movie]), restDelay: 0.5)
        ring.send(.time(10))
        ring.send(.pointer(at: 143, distance: 90))
        ring.send(.time(10.3))
        ring.send(.pointer(at: 143, distance: distance))

        ring.send(.time(11))

        #expect(ring.rest == nil)
        #expect(ring.added.isEmpty)
    }

    @Test func anAddedFormatIsNotRestedOnAgain() {
        var ring = RingModel.opened(with: Sample.mixed([Sample.photo], [Sample.movie]), restDelay: 0.5)

        ring.rest(at: 143, from: 10)

        #expect(ring.rest == nil)
    }

    @Test func addingJPEGAfterPNGReplacesIt() {
        var ring = RingModel.opened(with: Sample.mixed([Sample.photo], [Sample.movie]), restDelay: 0.5)
        ring.rest(at: 143, from: 10)

        ring.rest(at: -143, from: 11)

        #expect(ring.added == [.init(kind: .image, format: .jpeg, quality: .high, files: [Sample.photo])])
        #expect(ring.entries.map(\.isAdded) == [false, true, false])
        #expect(ring.caption == "JPEG added · drop to convert")

        ring.send(.pointer(at: 0, distance: 90))
        ring.send(.drop)

        #expect(ring.outcome == .convert([
            .init(kind: .image, format: .jpeg, quality: .high, files: [Sample.photo]),
            .init(kind: .video, format: .mp4, files: [Sample.movie]),
        ]))
    }

    @Test func addingAFormatForEachKindAddsBoth() {
        var ring = RingModel.opened(with: Sample.mixed([Sample.photo], [Sample.movie]), restDelay: 0.5)
        ring.rest(at: 143, from: 10)

        ring.rest(at: 0, from: 11)

        #expect(ring.added.map(\.format) == [.png, .mp4])
        #expect(ring.caption == "PNG + MP4 added · drop to convert")
    }

    @Test func addingMP4ThenDroppingOnPNGConvertsBothInThatOrder() {
        var ring = RingModel.opened(with: Sample.mixed([Sample.photo], [Sample.movie]), restDelay: 0.5)
        ring.rest(at: 0, from: 10)
        ring.send(.pointer(at: 143, distance: 90))

        #expect(ring.hub?.text == "MP4 + PNG · 2 files")

        ring.send(.drop)

        #expect(ring.outcome == .convert([
            .init(kind: .video, format: .mp4, files: [Sample.movie]),
            .init(kind: .image, format: .png, files: [Sample.photo]),
        ]))
    }

    @Test func aDropOnTheHubAfterAddingCancels() {
        var ring = RingModel.opened(with: Sample.mixed([Sample.photo], [Sample.movie]), restDelay: 0.5)
        ring.rest(at: 143, from: 10)
        ring.send(.pointer(at: 0, distance: 20))

        ring.send(.drop)

        #expect(ring.outcome == .cancel)
    }

    @Test func reopeningTheRingForgetsWhatWasAdded() {
        var ring = RingModel.opened(with: Sample.mixed([Sample.photo], [Sample.movie]), restDelay: 0.5)
        ring.rest(at: 143, from: 10)
        ring.send(.shift(down: false))

        ring.send(.shift(down: true))

        #expect(ring.added.isEmpty)
        #expect(ring.caption == "Rest on a format to add it, then drop on another")
    }

    @Test(arguments: [Sample.images([Sample.photo]), Sample.movies([Sample.movie])])
    func restingDoesNothingWithOneKindOfFile(offers: Offers) {
        var ring = RingModel.opened(with: offers, restDelay: 0.5)

        ring.rest(at: 180, from: 10)
        ring.send(.time(20))

        #expect(ring.rest == nil)
        #expect(ring.added.isEmpty)
        #expect(ring.entries.allSatisfy { !$0.isAdded })
    }

    @Test func restingOnAQualityAddsJPEGAtThatQuality() {
        var ring = RingModel.opened(with: Sample.mixed([Sample.photo], [Sample.movie]), restDelay: 0.5)
        ring.send(.option(down: true))

        ring.rest(at: 154, from: 10)

        #expect(ring.added == [.init(kind: .image, format: .jpeg, quality: .best, files: [Sample.photo])])
        #expect(ring.entries.map(\.isAdded) == [false, true, false, false, false])
        #expect(ring.caption == "JPEG 100% added · drop to convert")

        ring.send(.option(down: false))
        ring.send(.pointer(at: 0, distance: 90))
        ring.send(.drop)

        #expect(ring.outcome == .convert([
            .init(kind: .image, format: .jpeg, quality: .best, files: [Sample.photo]),
            .init(kind: .video, format: .mp4, files: [Sample.movie]),
        ]))
    }

    @Test func theRestStartsAtTheFirstTimeAfterItWhenNoTimeWasSentBefore() {
        var ring = RingModel.opened(with: Sample.mixed([Sample.photo], [Sample.movie]), restDelay: 0.5)
        ring.send(.pointer(at: 143, distance: 90))
        #expect(ring.rest?.deadline == nil)

        ring.send(.time(10))
        ring.send(.time(10.4))
        #expect(ring.added.isEmpty)

        ring.send(.time(10.5))
        #expect(ring.added.map(\.format) == [.png])
    }
}

extension RingModel {
    /// The pointer onto the entry at `degrees` at time `start`, resting there past the delay.
    mutating func rest(at degrees: Double, from start: TimeInterval) {
        send(.time(start))
        send(.pointer(at: degrees, distance: 90))
        send(.time(start + restDelay))
    }
}
