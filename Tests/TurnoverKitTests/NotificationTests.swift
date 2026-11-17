import Foundation
import Testing
import TurnoverKit
import TurnoverTestSupport

/// The notifications `Feedback` posts when a batch ends: one for a batch that took more than
/// about 3 seconds, one for failures, and one for outputs saved to Downloads. Quick, clean
/// batches post nothing.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct Notifications {
    let folder = try! ScratchFolder()
    let downloads = try! ScratchFolder()
    let clock = ManualClock()
    let turnstile = Turnstile()
    let posted = Posted()

    /// Runs `files`, holding conversions at their end until `seconds` have passed on the clock.
    func run(_ files: [URL], to actions: [any ConversionAction], taking seconds: Double,
             runner: JobRunner = JobRunner()) async -> Batch {
        let feedback = Feedback(clock: clock, notify: posted.append)
        let batch = runner.run(files, to: actions.map { turnstile.holding($0) })
        feedback.track(batch)
        #expect(await eventually { turnstile.running > 0 || batch.isFinished })
        clock.advance(by: .seconds(seconds))
        turnstile.open()
        await batch.waitUntilFinished()
        return batch
    }

    @Test func aBatchOverThreeSecondsSaysWhatItConvertedAndCanShowTheOutputs() async throws {
        let clips = try ["a", "b"].map { try folder.add(.movHEVCHDR, as: "\($0).mov") }

        let batch = await run(clips, to: [MP4Action()], taking: 3.5)

        #expect(posted.notices == [Notice(
            kind: .converted, title: "Converted 2 videos to MP4", body: "a.mp4 and b.mp4", files: batch.outputs)])
        #expect(batch.outputs.count == 2)
    }

    @Test func aSlowMixedBatchNamesEachKindAndFormat() async throws {
        let photos = try ["a", "b"].map { try folder.add(.heicRotated, as: "\($0).heic") }
        let clip = try folder.add(.movHEVCHDR, as: "clip.mov")

        let batch = await run(photos + [clip], to: [JPEGAction(), MP4Action()], taking: 3.5)

        #expect(posted.notices == [Notice(
            kind: .converted, title: "Converted 2 images to JPEG and 1 video to MP4", body: "a.jpg and 2 more",
            files: batch.outputs)])
        #expect(batch.outputs.count == 3)
    }

    @Test func aSlowBatchWithAFailurePostsBoth() async throws {
        let photo = try folder.add(.heicRotated, as: "photo.heic")
        let broken = try folder.add(Fixture.heicRotated.data.prefix(2000), as: "broken.heic")

        let batch = await run([photo, broken], to: [PNGAction()], taking: 3.5)

        #expect(posted.notices.map(\.kind) == [.converted, .failed])
        #expect(posted.notices.first?.title == "Converted 1 image to PNG")
        #expect(posted.notices.first?.files == batch.outputs)
    }

    @Test func aBatchOfThreeSecondsOrLessPostsNothing() async throws {
        let photo = try folder.add(.heicRotated, as: "photo.heic")

        let batch = await run([photo], to: [PNGAction()], taking: 2.9)

        #expect(batch.outputs.count == 1)
        #expect(posted.notices == [])
    }

    /// The Finder menu offers formats by extension, and the app converts by content. A PNG named
    /// `x.jpg` is offered PNG; converting it does nothing, and the user must hear why.
    @Test func aFileSkippedAtConversionIsPostedWithWhy() async throws {
        let renamed = try folder.add(.png, as: "x.jpg")

        let batch = await run([renamed], to: [PNGAction()], taking: 0.2)

        #expect(batch.outputs.isEmpty)
        #expect(posted.notices == [Notice(
            kind: .failed, title: "Couldn't convert x.jpg", body: "Already a PNG", files: [])])
    }

    @Test func filesSkippedAtConversionArePostedWithTheFailures() async throws {
        let renamed = try folder.add(.png, as: "x.jpg")
        let notes = try folder.add(.text, as: "notes.txt")
        let broken = try folder.add(Fixture.heicRotated.data.prefix(2000), as: "broken.heic")

        _ = await run([renamed, notes, broken], to: [PNGAction()], taking: 0.2)

        #expect(posted.notices == [Notice(
            kind: .failed, title: "Couldn't convert 3 files",
            body: """
                x.jpg: already a PNG
                notes.txt: not an image or a video (text)
                broken.heic: damaged or incomplete, can't be decoded
                """,
            files: [])])
    }

    @Test func aSlowBatchThatWasCancelledPostsNothing() async throws {
        let clip = try folder.add(.movHEVCHDR, as: "clip.mov")
        let feedback = Feedback(clock: clock, notify: posted.append)

        let batch = JobRunner().run([clip], to: [turnstile.holding(MP4Action())])
        feedback.track(batch)
        #expect(await turnstile.waitUntil(running: 1))
        clock.advance(by: .seconds(10))
        batch.cancel()
        await batch.waitUntilFinished()

        #expect(posted.notices == [])
    }

    @Test func aFailureIsPostedWithItsReasonEvenWhenTheBatchWasQuick() async throws {
        let photo = try folder.add(.heicRotated, as: "photo.heic")
        let broken = try folder.add(Fixture.heicRotated.data.prefix(2000), as: "broken.heic")

        let batch = await run([photo, broken], to: [PNGAction()], taking: 0.2)

        #expect(batch.outputs.count == 1)
        #expect(posted.notices == [Notice(
            kind: .failed, title: "Couldn't convert broken.heic", body: "Damaged or incomplete, can't be decoded",
            files: [])])
    }

    /// One notice for the batch, not a stack of them; each line is a file and its reason.
    @Test func severalFailuresArePostedTogetherWithEachReason() async throws {
        let broken = try folder.add(Fixture.heicRotated.data.prefix(2000), as: "broken.heic")
        let cut = try folder.add(Fixture.movHEVCHDR.data.prefix(20_000), as: "cut.mov")
        let missing = folder.url.appendingPathComponent("gone.heic")

        _ = await run([broken, cut, missing], to: [PNGAction(), MP4Action()], taking: 0.2)

        #expect(posted.notices == [Notice(
            kind: .failed, title: "Couldn't convert 3 files",
            body: """
                broken.heic: damaged or incomplete, can't be decoded
                cut.mov: damaged or incomplete, can't be decoded
                gone.heic: can't be read
                """,
            files: [])])
    }

    @Test func anOutputSavedToDownloadsIsPostedEvenWhenTheBatchWasQuick() async throws {
        let photo = try folder.add(.heicRotated, as: "photo.heic")
        try folder.makeReadOnly()

        let runner = JobRunner(converter: Converter(downloads: downloads.url))
        _ = await run([photo], to: [PNGAction()], taking: 0.2, runner: runner)

        #expect(posted.notices == [Notice(
            kind: .savedToDownloads, title: "Saved photo.png to Downloads",
            body: "The folder of photo.heic is read-only.",
            files: [downloads.url.appendingPathComponent("photo.png")])])
    }

    @Test func severalOutputsSavedToDownloadsArePostedTogether() async throws {
        let photo = try folder.add(.heicRotated, as: "photo.heic")
        let other = try folder.add(.webp, as: "other.webp")
        try folder.makeReadOnly()

        let runner = JobRunner(converter: Converter(downloads: downloads.url))
        _ = await run([photo, other], to: [JPEGAction()], taking: 0.2, runner: runner)

        #expect(posted.notices == [Notice(
            kind: .savedToDownloads, title: "Saved 2 files to Downloads",
            body: "The folders of the originals are read-only.",
            files: [downloads.url.appendingPathComponent("photo.jpg"),
                    downloads.url.appendingPathComponent("other.jpg")])])
    }

    /// One notice says both that the slow batch is done and where its output went.
    @Test func aSlowBatchSavedToDownloadsSaysSoInItsOneNotice() async throws {
        let clip = try folder.add(.movHEVCHDR, as: "clip.mov")
        try folder.makeReadOnly()

        let runner = JobRunner(converter: Converter(downloads: downloads.url))
        _ = await run([clip], to: [MP4Action()], taking: 4, runner: runner)

        #expect(posted.notices == [Notice(
            kind: .converted, title: "Converted 1 video to MP4",
            body: "Saved clip.mp4 to Downloads: the folder of clip.mov is read-only.",
            files: [downloads.url.appendingPathComponent("clip.mp4")])])
    }
}

/// The notices a test's `Feedback` posted, in order.
@MainActor
final class Posted {
    private(set) var notices: [Notice] = []
    func append(_ notice: Notice) { notices.append(notice) }
}
