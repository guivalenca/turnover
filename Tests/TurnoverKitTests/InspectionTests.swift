import Foundation
import Testing
import TurnoverKit
import TurnoverTestSupport
import UniformTypeIdentifiers

@Suite struct Inspection {
    let folder = try! ScratchFolder()

    @Test(arguments: [
        (Fixture.heicRotated, SourceFile.Kind.image, UTType.heic),
        (.jpeg, .image, .jpeg),
        (.png, .image, .png),
        (.webp, .image, .webP),
        (.movH264, .video, .quickTimeMovie),
        (.movHEVCHDR, .video, .quickTimeMovie),
        (.mp4H264, .video, .mpeg4Movie),
        (.pdf, .unsupported, .pdf),
        (.text, .unsupported, .plainText),
    ])
    func fixturesAreClassifiedByContent(fixture: Fixture, kind: SourceFile.Kind, type: UTType) throws {
        let file = try SourceFile(fixture.url)

        #expect(file.kind == kind)
        #expect(file.contentType == type)
    }

    @Test func aWrongExtensionDoesNotFoolInspection() throws {
        let jpegCalledPNG = try folder.add(.jpeg, as: "photo.png")
        let movieCalledJPEG = try folder.add(.movH264, as: "clip.jpg")
        let textCalledHEIC = try folder.add(.text, as: "notes.heic")

        #expect(try SourceFile(jpegCalledPNG).contentType == .jpeg)
        #expect(try SourceFile(movieCalledJPEG).kind == .video)
        #expect(try SourceFile(textCalledHEIC).kind == .unsupported)
    }
}
