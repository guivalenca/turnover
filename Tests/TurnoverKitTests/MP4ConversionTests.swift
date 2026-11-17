import Foundation
import Testing
import TurnoverKit
import TurnoverTestSupport

@Suite struct MP4Conversion {
    let folder = try! ScratchFolder()

    @Test func anH264MovieBecomesAnMP4NextToTheOriginal() async throws {
        let clip = try folder.add(.movH264, as: "clip.mov")

        let result = try await Converter().convert(clip, with: MP4Action())

        #expect(result.output == folder.url.appendingPathComponent("clip.mp4"))
        let mp4 = try await VideoFacts(result.output)
        #expect(["isom", "mp41", "mp42"].contains(mp4.majorBrand))
        #expect(mp4.videoCodec == "avc1")
        #expect(mp4.audioCodec == "aac ")
        #expect(try folder.fileNames() == ["clip.mov", "clip.mp4"])
        #expect(try Data(contentsOf: clip) == Fixture.movH264.data)
    }
}
