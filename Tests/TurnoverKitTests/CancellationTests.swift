import Foundation
import Testing
import TurnoverKit
import TurnoverTestSupport

/// Cancelling the task that runs a conversion stops it and leaves the folder as it was.
@Suite struct Cancellation {
    let folder = try! ScratchFolder()

    @Test(arguments: [Fixture.movHEVCHDR, .movH264])
    func cancellingAVideoStopsItPromptlyAndLeavesNothingBehind(fixture: Fixture) async throws {
        let clip = try folder.add(fixture, as: "clip.mov")
        let progress = ProgressRecorder()
        let stop = CancelSwitch()

        // Cancel at the first sign of progress: one frame in, of 60.
        let job = Task {
            try await Converter().convert(clip, with: MP4Action()) { fraction in
                progress.record(fraction)
                stop.pull()
            }
        }
        stop.arm(job)

        await #expect(throws: CancellationError.self) { try await job.value }
        #expect(try folder.fileNames() == ["clip.mov"])
        #expect(progress.values.max()! < 0.5)
    }

    /// A queued job cancelled before it runs. Image actions never check for cancellation, so
    /// this also shows that a finished output is withheld when the task is cancelled.
    @Test(arguments: [Fixture.heicRotated, .movHEVCHDR])
    func aConversionCancelledBeforeItStartsLeavesNothingBehind(fixture: Fixture) async throws {
        let file = try folder.add(fixture)
        let action: any ConversionAction = fixture == .heicRotated ? PNGAction() : MP4Action()

        let job = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await Converter().convert(file, with: action)
        }

        await #expect(throws: CancellationError.self) { try await job.value }
        #expect(try folder.fileNames() == [fixture.rawValue])
    }
}
