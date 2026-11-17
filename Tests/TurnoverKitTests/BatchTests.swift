import Foundation
import Testing
import TurnoverKit
import TurnoverTestSupport

/// Running many files at once through `JobRunner`: what each file becomes and what the batch reports.
@MainActor
@Suite struct Batches {
    let folder = try! ScratchFolder()

    @Test func convertsEachFileWithTheTargetForItsKind() async throws {
        let photo = try folder.add(.heicRotated, as: "photo.heic")
        let clip = try folder.add(.movHEVCHDR, as: "clip.mov")

        let batch = JobRunner().run([photo, clip], to: [PNGAction(), MP4Action()])
        await batch.waitUntilFinished()

        #expect(batch.outputs == [folder.url.appendingPathComponent("photo.png"),
                                  folder.url.appendingPathComponent("clip.mp4")])
        #expect(try ImageFacts(batch.outputs[0]).typeIdentifier == "public.png")
        #expect(try await VideoFacts(batch.outputs[1]).videoCodec == "avc1")
        #expect(try folder.fileNames() == ["clip.mov", "clip.mp4", "photo.heic", "photo.png"])
    }
}
