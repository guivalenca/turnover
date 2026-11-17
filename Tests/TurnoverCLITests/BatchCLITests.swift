import Darwin
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

    /// Ctrl-C cancels the batch and turnover exits 130 once every job has stopped and cleaned up.
    /// (The temporary folders can't be checked from here: macOS lets a process see only its own.
    /// The kit's cancellation tests check them.)
    @Test func ctrlCStopsTheBatchAndLeavesNoPartialFile() throws {
        let clips = try (1...4).map { try folder.add(.movHEVCHDR, as: "clip \($0).mov") }

        // Interrupt as soon as the first percentage shows: a transcode is under way.
        let run = try turnoverInTerminal(clips.map(\.path) + ["--to", "mp4"], interruptWhen: { $0.contains("%") })

        #expect(run.status == 130)
        let finished = run.output.split(separator: "\n").map { URL(fileURLWithPath: String($0)).lastPathComponent }
        #expect(finished.count < clips.count)
        #expect(try folder.fileNames() == (clips.map(\.lastPathComponent) + finished).sorted())
    }
}
