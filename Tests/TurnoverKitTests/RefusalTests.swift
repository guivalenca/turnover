import Foundation
import Testing
import TurnoverKit
import TurnoverTestSupport

/// Inputs a conversion must refuse or fail on, always leaving the folder as it was.
@Suite struct Refusals {
    let folder = try! ScratchFolder()

    @Test func aPNGIsNotConvertedToPNG() async throws {
        let png = try folder.add(.png, as: "logo.png")

        await #expect(throws: ConversionError.alreadyInFormat(png, format: .png)) {
            try await Converter().convert(png, with: PNGAction())
        }
        #expect(try folder.fileNames() == ["logo.png"])
    }

    @Test func aPNGWithAJPGExtensionIsStillRecognisedAndRefused() async throws {
        let png = try folder.add(.png, as: "logo.jpg")

        await #expect(throws: ConversionError.alreadyInFormat(png, format: .png)) {
            try await Converter().convert(png, with: PNGAction())
        }
        #expect(try folder.fileNames() == ["logo.jpg"])
    }

    @Test(arguments: [Fixture.text, .pdf, .movH264])
    func filesThatAreNotImagesAreRefused(fixture: Fixture) async throws {
        let file = try folder.add(fixture)

        await #expect(throws: ConversionError.self) {
            try await Converter().convert(file, with: PNGAction())
        }
        #expect(try folder.fileNames() == [fixture.rawValue])
    }

    @Test func unsupportedFilesAreNamedByTheirType() async throws {
        let text = try folder.add(.text)

        await #expect(throws: ConversionError.unsupported(text, typeDescription: "text")) {
            try await Converter().convert(text, with: PNGAction())
        }
    }

    // A truncated JPEG is not in the list: ImageIO decodes what is there and fills the rest
    // with grey, as Preview does, so it converts.
    @Test(arguments: [Fixture.heicRotated, .webp])
    func aTruncatedImageFailsAndLeavesNothingBehind(fixture: Fixture) async throws {
        let whole = fixture.data
        let broken = try folder.add(whole.prefix(whole.count / 2), as: "broken-\(fixture.rawValue)")

        await #expect(throws: ConversionError.damaged(broken)) {
            try await Converter().convert(broken, with: PNGAction())
        }
        #expect(try folder.fileNames() == [broken.lastPathComponent])
    }

    /// Cut anywhere after its header, a HEIC still opens, and the JPEG encoder never notices the
    /// missing picture: it wrote a blank JPEG. It must fail as damaged, whatever the format.
    @Test(arguments: [1_500, 3_000, 4_500, Fixture.heicRotated.data.count - 1], [OutputFormat.jpeg, .png])
    func aHEICCutShortFailsAsDamaged(kept: Int, format: OutputFormat) async throws {
        let broken = try folder.add(Fixture.heicRotated.data.prefix(kept), as: "broken.heic")

        await #expect(throws: ConversionError.damaged(broken)) {
            try await Converter().convert(broken, with: format.action())
        }
        #expect(try folder.fileNames() == ["broken.heic"])
    }
}

/// The same for videos and MP4.
@Suite struct VideoRefusals {
    let folder = try! ScratchFolder()

    @Test func anMP4IsNotConvertedToMP4() async throws {
        let mp4 = try folder.add(.mp4H264, as: "clip.mp4")

        await #expect(throws: ConversionError.alreadyInFormat(mp4, format: .mp4)) {
            try await Converter().convert(mp4, with: MP4Action())
        }
        #expect(try folder.fileNames() == ["clip.mp4"])
    }

    @Test(arguments: [Fixture.heicRotated, .text, .pdf])
    func filesThatAreNotVideosAreRefused(fixture: Fixture) async throws {
        let file = try folder.add(fixture)

        await #expect(throws: ConversionError.self) {
            try await Converter().convert(file, with: MP4Action())
        }
        #expect(try folder.fileNames() == [fixture.rawValue])
    }

    /// Cut halfway, the movie's index survives but half its frames are missing; cut at 2 KB,
    /// even the index is gone.
    @Test(arguments: [(Fixture.movHEVCHDR, 0.5), (.movH264, 0.5), (.movHEVCHDR, 0.06), (.movH264, 0.06)])
    func aTruncatedVideoFailsAndLeavesNothingBehind(fixture: Fixture, kept: Double) async throws {
        let whole = fixture.data
        let broken = try folder.add(whole.prefix(Int(Double(whole.count) * kept)), as: "broken.mov")

        await #expect(throws: ConversionError.damaged(broken)) {
            try await Converter().convert(broken, with: MP4Action())
        }
        #expect(try folder.fileNames() == ["broken.mov"])
        #expect(ConversionError.damaged(broken).localizedDescription == "broken.mov: damaged or incomplete, can't be decoded")
    }
}
