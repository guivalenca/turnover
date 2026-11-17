import Foundation
import Testing
import TurnoverTestSupport

/// `turnover <files…> --to jpeg [--quality best|high|small]`, end to end.
@Suite struct JPEGCLI {
    let folder = try! ScratchFolder()

    @Test func convertsAPhotoToJPGAtHighQualityByDefault() throws {
        let photo = try folder.add(.heicRotated, as: "photo.heic")

        let run = try turnover(photo.path, "--to", "jpeg")

        let output = folder.url.appendingPathComponent("photo.jpg")
        #expect(run.status == 0)
        #expect(run.output == output.path + "\n")
        #expect(run.messages == [])
        #expect(try folder.fileNames() == ["photo.heic", "photo.jpg"])
        #expect(try JPEGTables(output) == JPEGTables(quality: 0.85))
    }
}
