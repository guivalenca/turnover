import Foundation
import Testing
import TurnoverTestSupport

/// `turnover` with several files: they run as one batch.
@Suite struct BatchCLI {
    let folder = try! ScratchFolder()

    @Test func skipsAFileTheFormatDoesntFitWithANoteAndExitsZero() throws {
        let photo = try folder.add(.heicRotated, as: "a.heic")
        let clip = try folder.add(.movH264, as: "b.mov")

        let run = try turnover(photo.path, clip.path, "--to", "png")

        #expect(run.status == 0)
        #expect(run.output == folder.url.appendingPathComponent("a.png").path + "\n")
        #expect(run.messages == ["turnover: b.mov: skipped, can't be converted to PNG"])
        #expect(try folder.fileNames() == ["a.heic", "a.png", "b.mov"])
    }

    @Test func printsTheNewFilesInTheOrderGiven() throws {
        let slow = try folder.add(.movHEVCHDR, as: "slow.mov")
        let quick = try folder.add(.movH264, as: "quick.mov")

        let run = try turnover(slow.path, quick.path, "--to", "mp4")

        #expect(run.status == 0)
        #expect(run.output == [slow, quick].map { $0.deletingPathExtension().path + ".mp4\n" }.joined())
    }
}
