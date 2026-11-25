import Foundation
import Testing
import TurnoverTestSupport

/// `turnover <files…> --to jpeg [--quality best|high|small]`, end to end.
@Suite struct JPEGCLI {
    let folder = try! ScratchFolder()

    @Test func convertsAPhotoToJPGAtHighQualityByDefault() async throws {
        let photo = try folder.add(.heicRotated, as: "photo.heic")

        let run = try await turnover(photo.path, "--to", "jpeg")

        let output = folder.url.appendingPathComponent("photo.jpg")
        #expect(run.status == 0)
        #expect(run.output == output.path + "\n")
        #expect(run.messages == [])
        #expect(try folder.fileNames() == ["photo.heic", "photo.jpg"])
        #expect(try JPEGTables(output) == JPEGTables(quality: 0.85))
    }

    @Test(arguments: [
        (["--quality", "best"], 1.0),
        (["--quality", "high"], 0.85),
        (["--quality", "small"], 0.6),
        (["--quality=Small"], 0.6),
    ])
    func qualityPicksThePreset(option: [String], quality: Double) async throws {
        let photo = try folder.add(.heicRotated, as: "photo.heic")

        let run = try await turnover([photo.path, "--to", "jpeg"] + option)

        #expect(run.status == 0)
        #expect(try JPEGTables(folder.url.appendingPathComponent("photo.jpg")) == JPEGTables(quality: quality))
    }

    @Test(arguments: [
        (["--to", "jpeg", "--quality", "huge"], "unknown quality 'huge' (use best, high or small)"),
        (["--to", "jpeg", "--quality=85"], "unknown quality '85' (use best, high or small)"),
        (["--to", "jpeg", "--quality"], "--quality needs a quality"),
        (["--to", "png", "--quality", "small"], "--quality only applies to jpeg and smaller"),
    ])
    func aBadQualityIsAUsageError(arguments: [String], message: String) async throws {
        try folder.add(.heicRotated, as: "photo.heic")

        let run = try await turnover(["photo.heic"] + arguments, in: folder.url)

        #expect(run.status == 64)
        #expect(run.messages == ["turnover: \(message)"])
        #expect(run.errors.contains("usage: turnover"))
        #expect(try folder.fileNames() == ["photo.heic"])
    }

    @Test func theUsageListsTheQualities() async throws {
        let run = try await turnover("--help")

        #expect(run.status == 0)
        #expect(run.output.contains("--quality <quality>"))
        #expect(run.output.contains("best (100%), high (85%, the default), small (60%)"))
    }
}
