import Foundation
import Testing
import TurnoverTestSupport

/// `turnover` typed in a terminal: the progress line and Ctrl-C.
///
/// One at a time: on CI every test target runs in one process, and two of these side by side
/// mixed up their terminals there (one saw nothing, the other both outputs).
@Suite(.serialized) struct InTerminal {
    let folder = try! ScratchFolder()

    @Test func showsAPercentageWhileConvertingInATerminal() throws {
        let clip = try folder.add(.movHEVCHDR, as: "clip.mov")

        let run = try turnoverInTerminal(clip.path, "--to", "mp4")

        #expect(run.status == 0)
        #expect(run.output == folder.url.appendingPathComponent("clip.mp4").path + "\n")
        #expect(run.errors.contains("clip.mov"))
        #expect(run.errors.contains("%"))
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
