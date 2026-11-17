import Foundation
import RingModel
import Testing
import TurnoverKit

/// When the ring opens and closes: ⇧ during a drag of files, and nothing else.
@Suite struct Opening {
    @Test func shiftPressedMidDragOpensTheRing() {
        var ring = RingModel()

        ring.send(.dragStarted(shiftDown: false))
        ring.send(.shift(down: true))

        #expect(ring.phase == .open)
    }

    @Test func shiftHeldBeforeTheDragDoesNotOpenTheRing() {
        var ring = RingModel()

        ring.send(.dragStarted(shiftDown: true))
        ring.send(.shift(down: true))

        #expect(ring.phase == .dragging)
    }

    @Test func shiftHeldBeforeTheDragOpensTheRingWhenPressedAgain() {
        var ring = RingModel()

        ring.send(.dragStarted(shiftDown: true))
        ring.send(.shift(down: false))
        ring.send(.shift(down: true))

        #expect(ring.phase == .open)
    }

    @Test func shiftWithoutADragNeverOpensTheRing() {
        var ring = RingModel()

        ring.send(.shift(down: true))

        #expect(ring.phase == .idle)
    }

    @Test func releasingShiftClosesTheRingAndTheDragGoesOn() {
        var ring = RingModel()
        ring.send(.dragStarted(shiftDown: false))
        ring.send(.shift(down: true))

        ring.send(.shift(down: false))

        #expect(ring.phase == .dragging)
        #expect(ring.outcome == nil)
    }

    @Test func theRingReopensWhenShiftIsPressedAgain() {
        var ring = RingModel()
        ring.send(.dragStarted(shiftDown: false))
        ring.send(.shift(down: true))
        ring.send(.shift(down: false))

        ring.send(.shift(down: true))

        #expect(ring.phase == .open)
    }

    @Test func aDropElsewhereEndsTheDragWithNoOutcome() {
        var ring = RingModel()
        ring.send(.dragStarted(shiftDown: false))
        ring.send(.shift(down: true))
        ring.send(.shift(down: false))

        ring.send(.dragEnded)

        #expect(ring.phase == .idle)
        #expect(ring.outcome == nil)
    }

    @Test func shiftAfterTheDragEndedDoesNotOpenTheRing() {
        var ring = RingModel()
        ring.send(.dragStarted(shiftDown: false))
        ring.send(.dragEnded)

        ring.send(.shift(down: true))

        #expect(ring.phase == .idle)
    }
}
