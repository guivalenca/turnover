import Foundation
import Testing
import TurnoverKit
import TurnoverTestSupport

/// The menu bar item: it shows only while a batch has been running for more than about a second,
/// reports overall progress, and goes away shortly after everything has ended.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct MenuBarItem {
    let folder = try! ScratchFolder()
    let clock = ManualClock()
    let turnstile = Turnstile()

    @Test func appearsOnceABatchHasRunForASecond() async throws {
        let photo = try folder.add(.heicRotated, as: "photo.heic")
        let feedback = Feedback(clock: clock)

        let batch = JobRunner().run([photo], to: [turnstile.holding(PNGAction())])
        feedback.track(batch)
        #expect(await turnstile.waitUntil(running: 1))

        clock.advance(by: .milliseconds(900))
        #expect(!feedback.showsStatusItem)
        clock.advance(by: .milliseconds(200))
        #expect(feedback.showsStatusItem)

        turnstile.open()
        await batch.waitUntilFinished()
    }

    @Test func neverAppearsForABatchThatEndsWithinASecond() async throws {
        let photo = try folder.add(.heicRotated, as: "photo.heic")
        let feedback = Feedback(clock: clock)

        let batch = JobRunner().run([photo], to: [turnstile.holding(PNGAction())])
        feedback.track(batch)
        #expect(await turnstile.waitUntil(running: 1))
        clock.advance(by: .milliseconds(900))
        turnstile.open()
        await batch.waitUntilFinished()

        for _ in 1...10 {
            clock.advance(by: .milliseconds(500))
            #expect(!feedback.showsStatusItem)
        }
    }

    @Test func showsAHundredPercentForAMomentAfterTheBatchEndsThenGoesAway() async throws {
        let photo = try folder.add(.heicRotated, as: "photo.heic")
        let feedback = Feedback(clock: clock)

        let batch = JobRunner().run([photo], to: [turnstile.holding(PNGAction())])
        feedback.track(batch)
        #expect(await turnstile.waitUntil(running: 1))
        clock.advance(by: .seconds(4))
        turnstile.open()
        await batch.waitUntilFinished()

        #expect(feedback.showsStatusItem)
        #expect(feedback.progress == 1)
        clock.advance(by: .milliseconds(500))
        #expect(feedback.showsStatusItem)
        clock.advance(by: .seconds(2))
        #expect(!feedback.showsStatusItem)
    }

    /// A batch that ends early still counts until the item goes away, so the figure never drops.
    @Test func theOverallPercentageCoversEveryBatchRunningTogether() async throws {
        let first = try folder.add(.heicRotated, as: "first.heic")
        let second = try folder.add(.webp, as: "second.webp")
        let third = try folder.add(.jpeg, as: "third.jpg")
        let laterTurnstile = Turnstile()
        let feedback = Feedback(clock: clock)
        let runner = JobRunner()

        let early = runner.run([first], to: [turnstile.holding(PNGAction())])
        let late = runner.run([second, third], to: [laterTurnstile.holding(PNGAction())])
        feedback.track(early)
        feedback.track(late)
        #expect(await turnstile.waitUntil(running: 1))
        #expect(await laterTurnstile.waitUntil(running: 2))
        clock.advance(by: .seconds(2))
        #expect(feedback.showsStatusItem)
        #expect(feedback.progress == 0)

        turnstile.open()
        await early.waitUntilFinished()
        #expect(feedback.progress == 1.0 / 3)

        laterTurnstile.open()
        await late.waitUntilFinished()
        #expect(feedback.progress == 1)
    }

    /// The item doesn't flicker off and on; it starts again from 0% for the new batch.
    @Test func aBatchStartedWhileTheItemLingersKeepsItAndStartsFromZero() async throws {
        let photo = try folder.add(.heicRotated, as: "photo.heic")
        let other = try folder.add(.webp, as: "other.webp")
        let laterTurnstile = Turnstile()
        let feedback = Feedback(clock: clock)
        let runner = JobRunner()

        let done = runner.run([photo], to: [turnstile.holding(PNGAction())])
        feedback.track(done)
        #expect(await turnstile.waitUntil(running: 1))
        clock.advance(by: .seconds(2))
        turnstile.open()
        await done.waitUntilFinished()
        clock.advance(by: .milliseconds(500))

        let next = runner.run([other], to: [laterTurnstile.holding(PNGAction())])
        feedback.track(next)
        #expect(feedback.showsStatusItem)
        #expect(feedback.progress == 0)
        clock.advance(by: .seconds(3))
        #expect(feedback.showsStatusItem)

        laterTurnstile.open()
        await next.waitUntilFinished()
        clock.advance(by: .seconds(3))
        #expect(!feedback.showsStatusItem)
    }

    /// Two videos convert at a time, so the third waits. Cancelling one lets the next start.
    @Test func listsTheRunningAndWaitingJobsAndCancellingOneLeavesNoPartialFile() async throws {
        let clips = try ["a", "b", "c"].map { try folder.add(.movH264, as: "\($0).mov") }
        let feedback = Feedback(clock: clock)

        let batch = JobRunner().run(clips, to: [turnstile.holding(MP4Action())])
        feedback.track(batch)
        #expect(await turnstile.waitUntil(running: 2))
        #expect(feedback.runningJobs.map(\.source) == [clips[0], clips[1]])
        #expect(feedback.waitingJobs.map(\.source) == [clips[2]])

        feedback.runningJobs[0].cancel()
        #expect(await eventually { feedback.runningJobs.map(\.source) == [clips[1], clips[2]] })
        #expect(feedback.waitingJobs.isEmpty)
        #expect(batch.jobs[0].state == .cancelled)

        turnstile.open()
        await batch.waitUntilFinished()
        #expect(feedback.runningJobs.isEmpty)
        #expect(try folder.fileNames() == ["a.mov", "b.mov", "b.mp4", "c.mov", "c.mp4"])
    }

    @Test func cancelAllStopsEveryBatchShown() async throws {
        let clips = try ["a", "b", "c"].map { try folder.add(.movH264, as: "\($0).mov") }
        let photo = try folder.add(.heicRotated, as: "photo.heic")
        let feedback = Feedback(clock: clock)
        let runner = JobRunner()

        let videos = runner.run(clips, to: [turnstile.holding(MP4Action())])
        let images = runner.run([photo], to: [turnstile.holding(PNGAction())])
        feedback.track(videos)
        feedback.track(images)
        #expect(await turnstile.waitUntil(running: 3))

        feedback.cancelAll()
        await videos.waitUntilFinished()
        await images.waitUntilFinished()
        #expect((videos.jobs + images.jobs).allSatisfy { $0.state == .cancelled })
        #expect(try folder.fileNames() == ["a.mov", "b.mov", "c.mov", "photo.heic"])
    }
}
