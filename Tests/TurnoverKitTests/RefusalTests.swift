import Foundation
import Testing
import TurnoverKit
import TurnoverTestSupport

/// Inputs a conversion must refuse or fail on, always leaving the folder as it was.
@Suite struct Refusals {
    let folder = try! ScratchFolder()

    @Test func aPNGIsNotConvertedToPNG() async throws {
        let png = try folder.add(.png, as: "logo.png")

        await #expect(throws: ConversionError.alreadyInFormat(png, format: "PNG")) {
            try await Converter().convert(png, with: PNGAction())
        }
        #expect(try folder.fileNames() == ["logo.png"])
    }

    @Test func aPNGWithAJPGExtensionIsStillRecognisedAndRefused() async throws {
        let png = try folder.add(.png, as: "logo.jpg")

        await #expect(throws: ConversionError.alreadyInFormat(png, format: "PNG")) {
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
}
