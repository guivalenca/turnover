import Foundation
import Testing
import TurnoverKit
import TurnoverTestSupport

/// What a batch reports while it runs, for the menu bar's percentage and job list.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct BatchProgress {
    let folder = try! ScratchFolder()

    @Test func eachJobAndTheWholeBatchGoFromZeroToOne() async throws {
        let clip = try folder.add(.movHEVCHDR, as: "clip.mov")
        let photo = try folder.add(.heicRotated, as: "photo.heic")

        let batch = JobRunner().run([clip, photo], to: [MP4Action(), PNGAction()])
        let overall = Recording { batch.progress }
        let video = Recording { batch.jobs[0].progress }
        let image = Recording { batch.jobs[1].progress }
        await batch.waitUntilFinished()

        #expect(overall.values.first == 0)
        #expect(overall.values == overall.values.sorted())
        #expect(overall.values.contains { $0 > 0 && $0 < 1 })
        #expect(batch.progress == 1)

        #expect(video.values.first == 0)
        #expect(video.values == video.values.sorted())
        #expect(video.values.filter { $0 > 0 && $0 < 1 }.count > 10)
        #expect(image.values.first == 0)
        #expect(batch.jobs.map(\.progress) == [1, 1])
    }
}
