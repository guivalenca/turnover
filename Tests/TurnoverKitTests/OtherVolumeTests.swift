import Foundation
import Testing
import TurnoverKit
import TurnoverTestSupport

/// Outputs land next to originals on external drives and shares too, including volumes where
/// macOS has no temporary folder to offer. There the new file is still written somewhere on the
/// same volume first, so it appears whole, and nothing temporary is left behind.
@Suite(.timeLimit(.minutes(1))) struct OtherVolumes {
    let downloads = try! ScratchFolder()

    @Test func aPhotoConvertsNextToItsOriginalOnAVolumeWithNoTemporaryFolder() async throws {
        let disk = try DiskImage()
        let album = try disk.folder("Album")
        let photo = album.appendingPathComponent("photo.heic")
        try FileManager.default.copyItem(at: Fixture.heicRotated.url, to: photo)
        try disk.lockTopLevel()

        let result = try await Converter(downloads: downloads.url).convert(photo, with: PNGAction())

        #expect(result.output == album.appendingPathComponent("photo.png"))
        #expect(!result.savedToDownloads)
        #expect(try FileManager.default.contentsOfDirectory(atPath: album.path).sorted() == ["photo.heic", "photo.png"])
        #expect(try ImageFacts(result.output).typeIdentifier == "public.png")
    }

    @Test func aCancelledVideoOnSuchAVolumeLeavesNothingNextToItsOriginal() async throws {
        let disk = try DiskImage()
        let trip = try disk.folder("Trip")
        let clip = trip.appendingPathComponent("clip.mov")
        try FileManager.default.copyItem(at: Fixture.movHEVCHDR.url, to: clip)
        try disk.lockTopLevel()
        let stop = CancelSwitch()

        let job = Task {
            try await Converter(downloads: downloads.url).convert(clip, with: MP4Action()) { _ in stop.pull() }
        }
        stop.arm(job)

        await #expect(throws: CancellationError.self) { try await job.value }
        #expect(try FileManager.default.contentsOfDirectory(atPath: trip.path) == ["clip.mov"])
    }
}
