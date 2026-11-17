import Foundation
import RingModel
import Testing
import TurnoverKit

/// A drag of files Turnover can't convert gets a short hint instead of a ring, and stays a
/// normal drag.
@Suite struct Hint {
    let pdf = Offers(groups: [], skipped: [.unsupported(Sample.lease, typeDescription: "PDF document")])

    @Test func shiftDuringAPDFDragShowsAHintAndNoRing() {
        let ring = RingModel.opened(with: pdf)

        #expect(ring.hint == "lease.pdf: not an image or a video (PDF document)")
        #expect(ring.phase == .dragging)
        #expect(ring.entries.isEmpty)
    }

    @Test func theRingClosesForTheHintWhenTheFilesBecomeKnownAfterItOpened() {
        var ring = RingModel()
        ring.send(.dragStarted(shiftDown: false))
        ring.send(.shift(down: true))

        ring.send(.offers(pdf))

        #expect(ring.phase == .dragging)
        #expect(ring.hint == "lease.pdf: not an image or a video (PDF document)")
    }

    @Test func releasingShiftClearsTheHint() {
        var ring = RingModel.opened(with: pdf)

        ring.send(.shift(down: false))

        #expect(ring.hint == nil)
    }

    @Test func theDragEndingClearsTheHint() {
        var ring = RingModel.opened(with: pdf)

        ring.send(.dragEnded)

        #expect(ring.hint == nil)
        #expect(ring.outcome == nil)
    }

    @Test func convertibleFilesShowNoHint() {
        let ring = RingModel.opened(with: Sample.images([Sample.photo]))

        #expect(ring.hint == nil)
    }
}
