import Foundation
import Testing
import TurnoverTestSupport

@Suite struct MP4CLI {
    let folder = try! ScratchFolder()

    @Test func convertsAMovieToMP4AndPrintsItsPath() throws {
        let clip = try folder.add(.movHEVCHDR, as: "clip.mov")

        let run = try turnover(clip.path, "--to", "mp4")

        #expect(run.status == 0)
        #expect(run.output == folder.url.appendingPathComponent("clip.mp4").path + "\n")
        #expect(run.messages == [])
        #expect(!run.errors.contains("%"))
        #expect(try folder.fileNames() == ["clip.mov", "clip.mp4"])
    }

    @Test func anMP4IsRefusedWithAShortReason() throws {
        let clip = try folder.add(.mp4H264, as: "clip.mp4")

        let run = try turnover(clip.path, "--to", "mp4")

        #expect(run.status == 1)
        #expect(run.output == "")
        #expect(run.messages == ["turnover: clip.mp4: already an MP4"])
        #expect(try folder.fileNames() == ["clip.mp4"])
    }
}
