import Foundation
import Testing
import TurnoverKit
import TurnoverTestSupport

/// When the original's folder can't be written to (a disk image, a locked drive, a read-only
/// share), the new file goes to Downloads instead, and the result says so.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct DownloadsFallback {
    let folder = try! ScratchFolder()
    let downloads = try! ScratchFolder()

    @Test func aReadOnlyFolderSendsTheOutputsToDownloadsAndTheResultsSaySo() async throws {
        let photo = try folder.add(.heicRotated, as: "photo.heic")
        let clip = try folder.add(.movH264, as: "clip.mov")
        try folder.makeReadOnly()

        let runner = JobRunner(converter: Converter(downloads: downloads.url))
        let batch = runner.run([photo, clip], to: [PNGAction(), MP4Action()])
        await batch.waitUntilFinished()

        let results = batch.jobs.compactMap(\.result)
        #expect(results.map(\.output) == [downloads.url.appendingPathComponent("photo.png"),
                                          downloads.url.appendingPathComponent("clip.mp4")])
        #expect(results.map(\.savedToDownloads) == [true, true])
        #expect(try folder.fileNames() == ["clip.mov", "photo.heic"])
        #expect(try downloads.fileNames() == ["clip.mp4", "photo.png"])
        #expect(try ImageFacts(results[0].output).typeIdentifier == "public.png")
    }

    @Test func aWritableFolderKeepsTheOutputNextToTheOriginal() async throws {
        let photo = try folder.add(.heicRotated, as: "photo.heic")

        let runner = JobRunner(converter: Converter(downloads: downloads.url))
        let batch = runner.run([photo], to: [PNGAction()])
        await batch.waitUntilFinished()

        #expect(batch.jobs[0].result?.output == folder.url.appendingPathComponent("photo.png"))
        #expect(batch.jobs[0].result?.savedToDownloads == false)
        #expect(try downloads.fileNames() == [])
    }

    @Test func outputsInDownloadsAreNumberedAndKeepTheOriginalsDates() async throws {
        let photo = try folder.add(.heicRotated, as: "photo.heic")
        let recorded = Date(timeIntervalSince1970: 1_718_440_200)
        try FileManager.default.setAttributes([.creationDate: recorded, .modificationDate: recorded], ofItemAtPath: photo.path)
        try folder.makeReadOnly()
        try downloads.add(.png, as: "photo.png")

        let runner = JobRunner(converter: Converter(downloads: downloads.url))
        let batch = runner.run([photo], to: [PNGAction()])
        await batch.waitUntilFinished()

        let output = downloads.url.appendingPathComponent("photo 2.png")
        #expect(batch.jobs[0].result?.output == output)
        #expect(try downloads.fileNames() == ["photo 2.png", "photo.png"])
        #expect(downloads.url.appendingPathComponent("photo.png").contents == Fixture.png.data)
        let dates = try output.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        #expect(dates.creationDate == recorded)
        #expect(dates.contentModificationDate == recorded)
    }
}

extension DownloadsFallback {
    @Test func whenDownloadsCantBeWrittenToEitherTheJobFailsWithAShortReason() async throws {
        let photo = try folder.add(.heicRotated, as: "photo.heic")
        try folder.makeReadOnly()
        try downloads.makeReadOnly()

        let runner = JobRunner(converter: Converter(downloads: downloads.url))
        let batch = runner.run([photo], to: [PNGAction()])
        await batch.waitUntilFinished()

        #expect(batch.jobs[0].state == .failed(reason: "photo.heic: couldn't write the PNG (Permission denied)"))
        #expect(try folder.fileNames() == ["photo.heic"])
        #expect(try downloads.fileNames() == [])
    }
}

private extension URL {
    var contents: Data? { try? Data(contentsOf: self) }
}
