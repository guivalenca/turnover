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

    @Test func h264IsPassedThroughUntouchedInAFractionOfItsDuration() async throws {
        let clip = try folder.add(.movH264, as: "clip.mov")

        let clock = ContinuousClock()
        let start = clock.now
        let output = try await Converter().convert(clip, with: MP4Action()).output
        let elapsed = clock.now - start

        // The fixture plays for 2 s; a remux must take a small fraction of that.
        #expect(elapsed < .milliseconds(500))
        let mp4 = try await VideoFacts(output)
        #expect(try await mp4.videoSamplesDigest() == VideoFacts(clip).videoSamplesDigest())
        #expect((mp4.width, mp4.height) == (160, 90))
        #expect(mp4.frameRate == 30)
        #expect(abs(mp4.duration - 2) < 0.05)
    }

    @Test func hdrHEVCIsTranscodedTo8BitSDRH264() async throws {
        let clip = try folder.add(.movHEVCHDR, as: "clip.mov")

        let output = try await Converter().convert(clip, with: MP4Action()).output

        let mp4 = try await VideoFacts(output)
        #expect(mp4.videoCodec == "avc1")
        // Baseline, Main and High are the 8-bit 4:2:0 profiles every player decodes.
        #expect([66, 77, 100].contains(mp4.h264Profile))
        #expect(mp4.colorPrimaries == "ITU_R_709_2")
        #expect(mp4.transferFunction == "ITU_R_709_2")
        #expect(mp4.yCbCrMatrix == "ITU_R_709_2")
        #expect(mp4.audioCodec == "aac ")
        #expect(mp4.frameRate == 30)
        #expect(abs(mp4.duration - 2) < 0.05)
        #expect(try folder.fileNames() == ["clip.mov", "clip.mp4"])
    }

    @Test func aPortraitVideoStaysPortrait() async throws {
        // Stored 160×90 with a 90° display matrix, so it plays as 90×160.
        let clip = try folder.add(.movHEVCHDR, as: "clip.mov")

        let mp4 = try await VideoFacts(try await Converter().convert(clip, with: MP4Action()).output)

        #expect((mp4.displayWidth, mp4.displayHeight) == (90, 160))
    }
}
