import Foundation
import Testing
import TurnoverKit
import TurnoverTestSupport

/// What an MP4 conversion will involve, known before running it (for estimates).
@Suite struct MP4Planning {
    @Test(arguments: [(Fixture.movH264, true), (.movH264PCM, true), (.movH264Silent, true), (.movHEVCHDR, false)])
    func aPlanSaysWhetherTheVideoIsPassedThrough(fixture: Fixture, passesThrough: Bool) async throws {
        let plan = try await MP4Action().plan(for: SourceFile(fixture.url))

        #expect(plan.passesVideoThrough == passesThrough)
        #expect(abs(plan.duration - 2) < 0.05)
        #expect((plan.frameWidth, plan.frameHeight) == (160, 90))
        #expect(plan.frameRate == 30)
    }

    @Test func planningFourVideosTakesWellUnder100Milliseconds() async throws {
        // The fastest of three rounds: the first pays for loading AVFoundation, and on CI other
        // tests compete for the CPU.
        var times: [Duration] = []
        for _ in 1...3 {
            times.append(try await ContinuousClock().measure {
                for fixture in [Fixture.movH264, .movH264PCM, .movH264Silent, .movHEVCHDR] {
                    _ = try await MP4Action().plan(for: SourceFile(fixture.url))
                }
            })
        }

        #expect(times.min()! < .milliseconds(50))
    }

    @Test func aDamagedVideoCantBePlanned() async throws {
        let folder = try ScratchFolder()
        let broken = try folder.add(Fixture.movHEVCHDR.data.prefix(2000), as: "broken.mov")

        await #expect(throws: ConversionError.damaged(broken)) {
            try await MP4Action().plan(for: SourceFile(broken))
        }
    }
}
