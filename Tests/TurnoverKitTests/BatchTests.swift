import Foundation
import Testing
import TurnoverKit
import TurnoverTestSupport

/// Running many files at once through `JobRunner`: what each file becomes and what the batch reports.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct Batches {
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

    @Test func aFileOfAnotherKindIsSkippedAndTheRestConvert() async throws {
        let clip = try folder.add(.movH264, as: "clip.mov")
        let photo = try folder.add(.heicRotated, as: "photo.heic")

        let batch = JobRunner().run([clip, photo], to: [PNGAction()])
        await batch.waitUntilFinished()

        #expect(batch.jobs[0].state == .skipped(.notApplicable(clip, format: "PNG")))
        #expect(batch.outputs == [folder.url.appendingPathComponent("photo.png")])
        #expect(try folder.fileNames() == ["clip.mov", "photo.heic", "photo.png"])
    }

    /// With a target for each kind, the reason given is the one that concerns the file's own kind.
    @Test func aFileAlreadyInItsTargetFormatOrUnsupportedIsSkippedWithThatReason() async throws {
        let logo = try folder.add(.png, as: "logo.png")
        let clip = try folder.add(.mp4H264, as: "clip.mp4")
        let notes = try folder.add(.text)

        let batch = JobRunner().run([logo, clip, notes], to: [MP4Action(), PNGAction()])
        await batch.waitUntilFinished()

        #expect(batch.jobs.map(\.state) == [
            .skipped(.alreadyInFormat(logo, format: "PNG")),
            .skipped(.alreadyInFormat(clip, format: "MP4")),
            .skipped(.unsupported(notes, typeDescription: "text")),
        ])
        #expect(try folder.fileNames() == ["clip.mp4", "logo.png", "notes.txt"])
    }

    @Test func aCorruptFileFailsWithAShortReasonWhileTheOthersConvert() async throws {
        let photo = try folder.add(.heicRotated, as: "photo.heic")
        let broken = try folder.add(Fixture.heicRotated.data.prefix(2000), as: "broken.heic")
        let cut = try folder.add(Fixture.movHEVCHDR.data.prefix(20_000), as: "cut.mov")
        let clip = try folder.add(.movHEVCHDR, as: "clip.mov")
        let missing = folder.url.appendingPathComponent("gone.heic")

        let batch = JobRunner().run([photo, broken, cut, clip, missing], to: [PNGAction(), MP4Action()])
        await batch.waitUntilFinished()

        #expect(batch.jobs[1].state == .failed(reason: "broken.heic: damaged or incomplete, can't be decoded"))
        #expect(batch.jobs[2].state == .failed(reason: "cut.mov: damaged or incomplete, can't be decoded"))
        #expect(batch.jobs[4].state == .failed(reason: "gone.heic: can't be read"))
        #expect(batch.outputs == [folder.url.appendingPathComponent("photo.png"),
                                  folder.url.appendingPathComponent("clip.mp4")])
        #expect(try folder.fileNames() == ["broken.heic", "clip.mov", "clip.mp4", "cut.mov", "photo.heic", "photo.png"])
    }
}
