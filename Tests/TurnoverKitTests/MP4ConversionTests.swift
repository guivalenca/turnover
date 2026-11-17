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

        // The fastest of three runs: the first pays for loading AVFoundation, and on CI other
        // tests compete for the CPU.
        var times: [Duration] = []
        var output: URL!
        for _ in 1...3 {
            times.append(try await ContinuousClock().measure {
                output = try await Converter().convert(clip, with: MP4Action()).output
            })
        }

        // The fixture plays for 2 s; a remux must take a small fraction of that.
        #expect(times.min()! < .milliseconds(500))
        let mp4 = try await VideoFacts(output)
        #expect(try await mp4.videoSamplesDigest() == VideoFacts(clip).videoSamplesDigest())
        #expect((mp4.width, mp4.height) == (160, 90))
        #expect(mp4.frameRate == 30)
        #expect(abs(mp4.duration - 2) < 0.05)
    }

    @Test func otherAudioIsEncodedToAACWhileTheVideoIsPassedThrough() async throws {
        let clip = try folder.add(.movH264PCM, as: "clip.mov")

        let output = try await Converter().convert(clip, with: MP4Action()).output

        let mp4 = try await VideoFacts(output)
        #expect(mp4.audioCodec == "aac ")
        #expect(try await mp4.videoSamplesDigest() == VideoFacts(clip).videoSamplesDigest())
        #expect(abs(mp4.duration - 2) < 0.05)
    }

    @Test func aSilentVideoStaysSilent() async throws {
        let clip = try folder.add(.movH264Silent, as: "clip.mov")

        let mp4 = try await VideoFacts(try await Converter().convert(clip, with: MP4Action()).output)

        #expect(mp4.videoCodec == "avc1")
        #expect(mp4.audioCodec == nil)
    }

    @Test func theRecordingDateAndLocationAreKept() async throws {
        let clip = try folder.add(.movH264PCM, as: "clip.mov")

        let mp4 = try await VideoFacts(try await Converter().convert(clip, with: MP4Action()).output)

        #expect(mp4.creationDate == Date(timeIntervalSince1970: 1_718_440_200))  // 2024-06-15 08:30:00 UTC
        #expect(mp4.location?.hasPrefix("+48.8584+002.2945") == true)
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

    @Test func aTranscodeReportsProgressAlongTheWayAndEndsAtOne() async throws {
        let clip = try folder.add(.movHEVCHDR, as: "clip.mov")
        let progress = ProgressRecorder()

        _ = try await Converter().convert(clip, with: MP4Action(), progress: progress.record)

        #expect(progress.inBetween.count >= 10)
        #expect(progress.values.last == 1)
        #expect(progress.values == progress.values.sorted())
    }
}
