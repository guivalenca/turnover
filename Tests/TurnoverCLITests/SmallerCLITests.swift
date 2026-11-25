import Foundation
import Testing
import TurnoverTestSupport

/// `turnover <files…> --to smaller [--quality high|medium|small]`, end to end.
@Suite struct SmallerCLI {
    let folder = try! ScratchFolder()

    @Test(arguments: [([String](), 720), (["--quality", "high"], 1080), (["--quality=small"], 480)])
    func makesAnMP4SmallerAtTheQuality(option: [String], height: Int) async throws {
        let clip = try await folder.addBusyMP4(width: 2560, height: 1440, as: "clip.mp4")

        let run = try await turnover([clip.path, "--to", "smaller"] + option)

        let output = folder.url.appendingPathComponent("clip-s.mp4")
        #expect(run.status == 0)
        #expect(run.output == output.path + "\n")
        #expect(try await VideoFacts(output).height == height)
    }

    @Test func aBadQualityIsAUsageError() async throws {
        let clip = try folder.add(.mp4H264, as: "clip.mp4")

        let run = try await turnover(clip.path, "--to", "smaller", "--quality", "best")

        #expect(run.status == 64)
        #expect(run.messages == ["turnover: unknown quality 'best' (use high, medium or small)"])
    }

    @Test func offersListTheQualities() async throws {
        let clip = try await folder.addBusyMP4(width: 1280, height: 720, as: "clip.mp4")

        let run = try await turnover("offers", clip.path)

        #expect(run.status == 0)
        #expect(try run.output.contains(Regex(#"^Videos \(1 file\)\n  Smaller MP4  1 file   High ~.+ [KM]B, Medium ~.+ [KM]B \(default\), Small ~.+ [KM]B\n$"#)))
    }
}
