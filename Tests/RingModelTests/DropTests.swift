import Foundation
import RingModel
import Testing
import TurnoverKit

/// What a drop on the open ring converts, and when it converts nothing.
@Suite struct Drop {
    @Test func aDropOnAnEntryConvertsItsFiles() {
        var ring = RingModel.opened(with: Sample.images([Sample.photo, Sample.photo2]))
        ring.send(.pointer(at: 180, distance: 90))

        ring.send(.drop)

        #expect(ring.outcome == .convert([.init(kind: .image, format: .png, files: [Sample.photo, Sample.photo2])]))
        #expect(ring.phase == .idle)
    }

    @Test(arguments: [JPEGQuality.small, .best])
    func aDropOnJPEGUsesTheDefaultPreset(defaultQuality: JPEGQuality) {
        var ring = RingModel.opened(with: Sample.images([Sample.photo], jpegQuality: defaultQuality))
        ring.send(.pointer(at: 0, distance: 90))

        ring.send(.drop)

        #expect(ring.outcome == .convert([.init(kind: .image, format: .jpeg, quality: defaultQuality, files: [Sample.photo])]))
    }

    @Test func aDropOnTheHubCancels() {
        var ring = RingModel.opened(with: Sample.images([Sample.photo]))
        ring.send(.pointer(at: 180, distance: 20))

        ring.send(.drop)

        #expect(ring.outcome == .cancel)
        #expect(ring.phase == .idle)
    }

    @Test func aDropOutsideTheRingCancels() {
        var ring = RingModel.opened(with: Sample.images([Sample.photo]))
        ring.send(.pointer(at: 180, distance: 300))

        ring.send(.drop)

        #expect(ring.outcome == .cancel)
    }

    @Test func aDropBeforeThePointerMovedCancels() {
        var ring = RingModel.opened(with: Sample.images([Sample.photo]))

        ring.send(.drop)

        #expect(ring.outcome == .cancel)
    }

    @Test func aDropBeforeTheFilesAreKnownCancels() {
        var ring = RingModel()
        ring.send(.dragStarted(shiftDown: false))
        ring.send(.shift(down: true))
        ring.send(.pointer(at: 180, distance: 90))

        ring.send(.drop)

        #expect(ring.outcome == .cancel)
    }

    @Test func theNextDragStartsWithNoOutcome() {
        var ring = RingModel.opened(with: Sample.images([Sample.photo]))
        ring.send(.drop)

        ring.send(.dragStarted(shiftDown: false))

        #expect(ring.outcome == nil)
    }

    @Test func escCancels() {
        var ring = RingModel.opened(with: Sample.images([Sample.photo]))
        ring.send(.pointer(at: 180, distance: 90))

        ring.send(.escape)

        #expect(ring.outcome == .cancel)
        #expect(ring.phase == .idle)
    }

    @Test func shiftAfterEscDoesNotReopenTheRing() {
        var ring = RingModel.opened(with: Sample.images([Sample.photo]))
        ring.send(.escape)

        ring.send(.shift(down: false))
        ring.send(.shift(down: true))

        #expect(ring.phase == .idle)
    }

    @Test func aReopenedRingIsCentredOnThePointer() {
        var ring = RingModel.opened(with: Sample.images([Sample.photo]))
        ring.send(.pointer(at: 180, distance: 90))
        ring.send(.shift(down: false))

        ring.send(.shift(down: true))

        #expect(ring.highlighted == nil)
    }

    @Test func theDragEndingWhileTheRingIsOpenCancels() {
        var ring = RingModel.opened(with: Sample.images([Sample.photo]))
        ring.send(.pointer(at: 180, distance: 300))

        ring.send(.dragEnded)

        #expect(ring.outcome == .cancel)
        #expect(ring.phase == .idle)
    }
}
