import Foundation
import Testing
import TurnoverKit
import TurnoverTestSupport

/// How many conversions a `JobRunner` runs at once: images side by side, videos two at a time.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct Concurrency {
    let folder = try! ScratchFolder()

    @Test func imagesConvertMoreThanTwoAtOnce() async throws {
        let photos = try (1...4).map { try folder.add(.heicRotated, as: "photo \($0).heic") }
        let turnstile = Turnstile()

        let batch = JobRunner().run(photos, to: [turnstile.holding(PNGAction())])

        #expect(await turnstile.waitUntil(running: 3))
        turnstile.open()
        await batch.waitUntilFinished()
        #expect(batch.outputs.count == 4)
    }

    @Test func noMoreThanTwoVideosConvertAtOnce() async throws {
        let clips = try (1...4).map { try folder.add(.movH264, as: "clip \($0).mov") }
        let turnstile = Turnstile()

        let batch = JobRunner().run(clips, to: [turnstile.holding(MP4Action())])

        #expect(await turnstile.waitUntil(running: 2))
        try await Task.sleep(for: .milliseconds(300))
        #expect(turnstile.running == 2)
        turnstile.open()
        await batch.waitUntilFinished()
        #expect(turnstile.mostAtOnce == 2)
        #expect(batch.outputs.count == 4)
    }

    @Test func theVideoLimitHoldsAcrossBatches() async throws {
        let clips = try (1...4).map { try folder.add(.movH264, as: "clip \($0).mov") }
        let turnstile = Turnstile()
        let runner = JobRunner()

        let first = runner.run(Array(clips[..<2]), to: [turnstile.holding(MP4Action())])
        let second = runner.run(Array(clips[2...]), to: [turnstile.holding(MP4Action())])

        #expect(await turnstile.waitUntil(running: 2))
        try await Task.sleep(for: .milliseconds(300))
        #expect(turnstile.running == 2)
        turnstile.open()
        await first.waitUntilFinished()
        await second.waitUntilFinished()
        #expect(turnstile.mostAtOnce == 2)
        #expect(first.outputs.count + second.outputs.count == 4)
    }

    @Test func videosDontHoldUpImages() async throws {
        let clips = try (1...2).map { try folder.add(.movH264, as: "clip \($0).mov") }
        let photo = try folder.add(.heicRotated, as: "photo.heic")
        let turnstile = Turnstile()

        let batch = JobRunner().run(clips + [photo], to: [turnstile.holding(MP4Action()), PNGAction()])
        #expect(await eventually { batch.jobs[2].isFinished })
        #expect(turnstile.running == 2)
        #expect(batch.outputs == [folder.url.appendingPathComponent("photo.png")])
        turnstile.open()
        await batch.waitUntilFinished()
    }
}
