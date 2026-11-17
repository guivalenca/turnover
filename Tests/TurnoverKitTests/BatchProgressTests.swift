import Foundation
import Synchronization
import Testing
import TurnoverKit
import TurnoverTestSupport

/// What a batch reports while it runs, for the menu bar's percentage and job list.
///
/// One test at a time: one of them blocks the main actor, which would starve the others' recordings.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1))) struct BatchProgress {
    let folder = try! ScratchFolder()

    @Test func eachJobAndTheWholeBatchGoFromZeroToOne() async throws {
        let clip = try folder.add(.movHEVCHDR, as: "clip.mov")
        let photo = try folder.add(.heicRotated, as: "photo.heic")

        let batch = JobRunner().run([clip, photo], to: [MP4Action(), PNGAction()])
        let overall = Recording { batch.progress }
        let video = Recording { batch.jobs[0].progress }
        let image = Recording { batch.jobs[1].progress }
        await batch.waitUntilFinished()

        #expect(overall.values.first == 0)
        #expect(overall.values == overall.values.sorted())
        #expect(overall.values.contains { $0 > 0 && $0 < 1 })
        #expect(batch.progress == 1)

        #expect(video.values.first == 0)
        #expect(video.values == video.values.sorted())
        #expect(video.values.contains { $0 > 0 && $0 < 1 })
        #expect(image.values.first == 0)
        #expect(batch.jobs.map(\.progress) == [1, 1])
    }

    @Test func theRunnerListsItsBatchesUntilEachFinishes() async throws {
        let clip = try folder.add(.movH264, as: "clip.mov")
        let photo = try folder.add(.heicRotated, as: "photo.heic")
        let turnstile = Turnstile()
        let runner = JobRunner()

        let slow = runner.run([clip], to: [turnstile.holding(MP4Action())])
        let quick = runner.run([photo], to: [PNGAction()])
        #expect(runner.batches.map(\.id) == [slow.id, quick.id])

        await quick.waitUntilFinished()
        #expect(runner.batches.map(\.id) == [slow.id])
        #expect(slow.finishDate == nil)
        let finish = try #require(quick.finishDate)
        #expect(quick.startDate <= finish)

        turnstile.open()
        await slow.waitUntilFinished()
        #expect(runner.batches.isEmpty)
        #expect(slow.finishDate != nil)
    }

    @Test func anEmptyBatchIsFinishedAtOnceAndNeverListed() async {
        let runner = JobRunner()

        let batch = runner.run([], to: [PNGAction()])

        #expect(batch.isFinished)
        #expect(batch.progress == 1)
        #expect(runner.batches.isEmpty)
        await batch.waitUntilFinished()
    }

    /// For a terminal's progress line: the reports reach the handler on the conversion's thread,
    /// even while the main actor is too busy to update `progress`.
    @Test func aReportingHandlerHearsEachJobEvenWhileTheMainActorIsBusy() async throws {
        let photo = try folder.add(.heicRotated, as: "photo.heic")
        let clip = try folder.add(.movHEVCHDR, as: "clip.mov")
        let reports = Reports()

        let batch = JobRunner().run([photo, clip], to: [PNGAction(), MP4Action()], reporting: reports.record)
        // Once the conversion has started (on the main actor, before it moves off it), hold the
        // main actor, deliberately, until the video says it is done.
        #expect(await eventually { !reports.of(1).isEmpty })
        let deadline = ContinuousClock.now + .seconds(30)
        while reports.of(1).last != 1, ContinuousClock.now < deadline { usleep(1000) }

        #expect(reports.of(1).last == 1)
        #expect(reports.of(1).contains { $0 > 0 && $0 < 1 })
        #expect(batch.jobs[1].progress < 1)
        await batch.waitUntilFinished()
        #expect(reports.of(0) == [1])
    }
}

/// Every (job index, fraction) a reporting handler received, from any thread.
private final class Reports: Sendable {
    private let log = Mutex<[(Int, Double)]>([])

    @Sendable func record(_ job: Int, _ fraction: Double) {
        log.withLock { $0.append((job, fraction)) }
    }

    func of(_ job: Int) -> [Double] {
        log.withLock { $0.filter { $0.0 == job }.map(\.1) }
    }
}
