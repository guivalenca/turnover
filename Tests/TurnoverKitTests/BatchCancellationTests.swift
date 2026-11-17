import Foundation
import Testing
import TurnoverKit
import TurnoverTestSupport

/// Cancelling jobs in a batch: each stops alone and leaves nothing behind.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct BatchCancellation {
    let folder = try! ScratchFolder()

    @Test func cancellingARunningJobLeavesNoOutputAndTheOthersGoOn() async throws {
        let clips = try (1...3).map { try folder.add(.movHEVCHDR, as: "clip \($0).mov") }
        let turnstile = Turnstile()
        let batch = JobRunner().run(clips, to: [turnstile.holding(MP4Action())])
        // Clips 1 and 2 are transcoded, their outputs written but not yet in place.
        #expect(await turnstile.waitUntil(running: 2))

        batch.jobs[0].cancel()

        #expect(await eventually { batch.jobs[0].isFinished })
        #expect(batch.jobs[0].state == .cancelled)
        turnstile.open()
        await batch.waitUntilFinished()
        #expect(batch.outputs == [folder.url.appendingPathComponent("clip 2.mp4"),
                                  folder.url.appendingPathComponent("clip 3.mp4")])
        #expect(try folder.fileNames() == ["clip 1.mov", "clip 2.mov", "clip 2.mp4", "clip 3.mov", "clip 3.mp4"])
        #expect(turnstile.destinations.count == 3)
        #expect(turnstile.destinations.allSatisfy { $0.folderIsGone })
    }

    /// The runner converts one image per core at once. Those conversions must not hold the threads
    /// everything async shares, or a cancelled video stays "running" until a photo is done.
    @Test func cancellingAVideoDoesntWaitForThePhotosConvertingAlongside() async throws {
        let clip = try folder.add(.movH264, as: "clip.mov")
        let turnstile = Turnstile()
        let runner = JobRunner()
        let video = runner.run([clip], to: [turnstile.holding(MP4Action())])
        #expect(await turnstile.waitUntil(running: 1))
        // As many 12-megapixel photos as the runner converts at once.
        let first = try await mosaic(in: folder, of: .heicRotated, width: 4000, height: 3000, as: "photo 1.jpg")
        let photos = try [first] + (2...ProcessInfo.processInfo.activeProcessorCount).map { index in
            let copy = folder.url.appendingPathComponent("photo \(index).jpg")
            try FileManager.default.copyItem(at: first, to: copy)
            return copy
        }
        let images = runner.run(photos, to: [PNGAction()])
        #expect(await eventually { images.jobs.allSatisfy { $0.state == .running } })

        video.jobs[0].cancel()

        #expect(await eventually { video.jobs[0].isFinished })
        #expect(video.jobs[0].state == .cancelled)
        #expect(images.jobs.allSatisfy { !$0.isFinished }, "the cancel waited for a photo to convert")
        await images.waitUntilFinished()
    }

    @Test func aJobCancelledWhileWaitingNeverStarts() async throws {
        let clips = try (1...3).map { try folder.add(.movH264, as: "clip \($0).mov") }
        let turnstile = Turnstile()
        let batch = JobRunner().run(clips, to: [turnstile.holding(MP4Action())])
        #expect(await turnstile.waitUntil(running: 2))
        #expect(batch.jobs[2].state == .waiting)

        batch.jobs[2].cancel()

        #expect(batch.jobs[2].state == .cancelled)
        turnstile.open()
        await batch.waitUntilFinished()
        #expect(turnstile.started == 2)
        #expect(try folder.fileNames() == ["clip 1.mov", "clip 1.mp4", "clip 2.mov", "clip 2.mp4", "clip 3.mov"])
    }

    @Test func cancellingTheBatchStopsEveryJobAndLeavesTheFolderAsItWas() async throws {
        let clips = try (1...3).map { try folder.add(.movHEVCHDR, as: "clip \($0).mov") }
        let photo = try folder.add(.heicRotated, as: "photo.heic")
        let turnstile = Turnstile()
        let batch = JobRunner().run(clips + [photo], to: [turnstile.holding(MP4Action()), turnstile.holding(PNGAction())])
        #expect(await turnstile.waitUntil(running: 3))

        batch.cancel()

        await batch.waitUntilFinished()
        #expect(batch.jobs.map(\.state) == [.cancelled, .cancelled, .cancelled, .cancelled])
        #expect(try folder.fileNames() == ["clip 1.mov", "clip 2.mov", "clip 3.mov", "photo.heic"])
        #expect(turnstile.destinations.count == 3)
        #expect(turnstile.destinations.allSatisfy { $0.folderIsGone })
    }
}

private extension URL {
    /// Whether the folder holding this temporary file has been removed.
    var folderIsGone: Bool { !FileManager.default.fileExists(atPath: deletingLastPathComponent().path) }
}
