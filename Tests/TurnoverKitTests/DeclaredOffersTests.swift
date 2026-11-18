import Foundation
import Testing
import TurnoverKit
import TurnoverTestSupport

/// Offers worked out from each file's declared type, without opening the files: what the
/// sandboxed Finder extension can do, since it may read the selection's metadata but not its
/// contents.
@Suite struct OffersFromDeclaredTypes {
    let folder = try! ScratchFolder()

    @Test func aHEICIsOfferedPNGAndJPEGEvenWhenItsContentsCantBeRead() throws {
        let photo = try folder.add(.heicRotated, as: "photo.heic")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: photo.path)

        let offers = Offers(declaredTypesOf: [photo])

        #expect(offers.groups.map(\.kind) == [.image])
        #expect(offers.targets.map(\.format) == [.png, .jpeg])
        #expect(offers.targets.map(\.files) == [[photo], [photo]])
    }

    /// The bytes are never looked at: a file is offered what its name promises.
    @Test(arguments: [
        ("clip.mov", [OutputFormat.mp4]),
        ("IMG_0001.MOV", [.mp4]),
        ("encoded.m4v", [.mp4]),
        ("sticker.webp", [.png, .jpeg]),
        ("scan.tiff", [.png, .jpeg]),
        ("logo.png", [.jpeg]),
        ("IMG_0002.JPG", [.png]),
    ])
    func eachFileIsOfferedWhatItsNamePromises(name: String, offered: [OutputFormat]) throws {
        let file = try folder.add(Data("not really media".utf8), as: name)

        #expect(Offers(declaredTypesOf: [file]).targets.map(\.format) == offered)
    }

    @Test func eachMenuItemSaysHowManyOfTheSelectedFilesItConverts() throws {
        let photo = try folder.add(.heicRotated, as: "IMG_0001.heic")
        let logo = try folder.add(.png, as: "logo.png")
        let movie = try folder.add(.movH264, as: "clip.mov")
        let screenshot = try folder.add(.png, as: "screenshot.png")
        let notes = try folder.add(.text)

        let offers = Offers(declaredTypesOf: [photo, logo, movie, notes, screenshot])

        #expect(offers.targets.map(\.menuTitle) == ["PNG (1 image)", "JPEG (3 images)", "MP4 (1 video)"])
        #expect(offers.targets.map(\.files) == [[photo], [photo, logo, screenshot], [movie]])
    }

    @Test func mp4sDocumentsFoldersAndMissingFilesAreOfferedNothing() throws {
        let mp4 = try folder.add(.mp4H264, as: "clip.mp4")
        let pdf = try folder.add(.pdf)
        let svg = try folder.add(Data("<svg/>".utf8), as: "drawing.svg")
        let subfolder = folder.url.appendingPathComponent("Album.heic", isDirectory: true)
        try FileManager.default.createDirectory(at: subfolder, withIntermediateDirectories: false)
        let missing = folder.url.appendingPathComponent("gone.heic")

        let offers = Offers(declaredTypesOf: [mp4, pdf, svg, subfolder, missing])

        #expect(offers.targets == [])
        #expect(offers.skipped.map(\.localizedDescription) == [
            "clip.mp4: already an MP4",
            "document.pdf: not an image or a video (PDF document)",
            "drawing.svg: not an image or a video (SVG image)",
            "Album.heic: not an image or a video (folder)",
            "gone.heic: can't be read",
        ])
    }
}
