import Foundation
import Testing
import TurnoverKit
import TurnoverTestSupport

/// Making an MP4 smaller, at a lower quality. One test at a time: each encodes videos, and the
/// timing tests run alongside.
@Suite(.serialized) struct MakingAnMP4Smaller {
    let folder = try! ScratchFolder()

    @Test func theSmallerVideoAppearsNextToTheOriginalWhichIsUntouched() async throws {
        let clip = try await folder.addBusyMP4(width: 1280, height: 720, as: "clip.mp4")
        let before = try Data(contentsOf: clip)

        let result = try await Converter().convert(clip, with: SmallerAction())

        #expect(result.output == folder.url.appendingPathComponent("clip-s.mp4"))
        #expect(try bytes(result.output) < before.count / 2)
        #expect(try Data(contentsOf: clip) == before)
        let smaller = try await VideoFacts(result.output)
        #expect(smaller.videoCodec == "avc1")
        #expect([66, 77, 100].contains(smaller.h264Profile))
        #expect(smaller.frameRate == 30)
        #expect(abs(smaller.duration - 1) < 0.05)
    }

    @Test(arguments: [(VideoQuality.high, 1920, 1080), (.medium, 1280, 720), (.small, 854, 480)])
    func eachQualityHasALargestFrame(quality: VideoQuality, width: Int, height: Int) async throws {
        let clip = try await folder.addBusyMP4(width: 2560, height: 1440, as: "clip.mp4")

        let output = try await Converter().convert(clip, with: SmallerAction(quality: quality)).output

        let smaller = try await VideoFacts(output)
        #expect((smaller.width, smaller.height) == (width, height))
    }

    @Test func theNameIsNumberedWhenTakenAndNeverGrowsASecondS() async throws {
        let clip = try await folder.addBusyMP4(width: 1280, height: 720, as: "clip.mp4")

        let first = try await Converter().convert(clip, with: SmallerAction(quality: .high)).output
        let second = try await Converter().convert(clip, with: SmallerAction(quality: .small)).output
        let again = try await Converter().convert(first, with: SmallerAction(quality: .small)).output

        #expect([first, second, again].map(\.lastPathComponent) == ["clip-s.mp4", "clip-s 2.mp4", "clip-s 3.mp4"])
    }

    @Test func aSmallFrameIsNeverEnlarged() async throws {
        let clip = try await folder.addBusyMP4(width: 640, height: 360, as: "clip.mp4")

        let smaller = try await VideoFacts(try await Converter().convert(clip, with: SmallerAction(quality: .high)).output)

        #expect((smaller.width, smaller.height) == (640, 360))
    }

    @Test func aPortraitVideoStaysPortraitAndItsShorterSideCounts() async throws {
        let clip = try await folder.addBusyMP4(width: 1920, height: 1080, turned: true, as: "clip.mp4")

        let smaller = try await VideoFacts(try await Converter().convert(clip, with: SmallerAction(quality: .medium)).output)

        #expect((smaller.displayWidth, smaller.displayHeight) == (720, 1280))
    }

    @Test func aVideoThatCantGetSmallerIsRefusedAndLeavesNothingBehind() async throws {
        let clip = try await folder.addBusyMP4(width: 320, height: 180, still: true, as: "clip.mp4")
        // Again and again at High, until a pass no longer helps.
        var last = clip
        var refused = false
        for _ in 1...30 where !refused {
            let names = try folder.fileNames()
            do {
                last = try await Converter().convert(last, with: SmallerAction(quality: .high)).output
            } catch {
                #expect(error as? ConversionError == .notSmaller(last))
                #expect(error.localizedDescription == "\(last.lastPathComponent): can't be made any smaller")
                #expect(try folder.fileNames() == names)
                refused = true
            }
        }
        #expect(refused)
    }

    @Test(arguments: [Fixture.movH264, .movHEVCHDR, .heicRotated])
    func onlyMP4sAreTaken(fixture: Fixture) throws {
        #expect(!SmallerAction().accepts(try SourceFile(fixture.url)))
    }

    @Test func aDamagedMP4IsRefused() async throws {
        let whole = Fixture.mp4H264.data
        let broken = try folder.add(whole.prefix(whole.count / 2), as: "broken.mp4")

        await #expect(throws: ConversionError.damaged(broken)) {
            try await Converter().convert(broken, with: SmallerAction())
        }
        #expect(try folder.fileNames() == ["broken.mp4"])
    }

    @Test func theEstimatesAreCloseToTheRealSizes() async throws {
        let clip = try await folder.addBusyMP4(width: 1280, height: 720, as: "clip.mp4")

        let offers = await Offers(estimating: [clip])

        let target = try #require(offers.targets.first)
        #expect(target.quality == .video(.medium))
        #expect(target.presets.map(\.quality) == [.video(.high), .video(.medium), .video(.small)])
        #expect(target.estimate == target.presets[1].estimate)
        let sizes = target.presets.compactMap(\.estimate.bytes)
        #expect(sizes.count == 3 && sizes == sizes.sorted(by: >))
        for (preset, size) in zip(target.presets, sizes) {
            let output = try await Converter().convert(clip, with: target.format.action(quality: preset.quality)).output
            let ratio = Double(size) / Double(try bytes(output))
            #expect(ratio > 0.5 && ratio < 2, "\(preset.quality.name): \(ratio)")
        }
    }

    private func bytes(_ file: URL) throws -> Int {
        try Data(contentsOf: file).count
    }
}
