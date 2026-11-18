import Foundation
import Testing
import TurnoverKit
import TurnoverTestSupport

/// An image dragged out of a web page has no file of its own: it is staged in a temporary
/// folder, and what the ring offers for it is saved into the folder the drop chose, as PNG, as
/// JPEG, or as it is (Original).
@MainActor
@Suite(.timeLimit(.minutes(1))) struct SavingADraggedImage {
    let staging = try! ScratchFolder()
    let destination = try! ScratchFolder()
    let downloads = try! ScratchFolder()

    // MARK: Into a folder

    @Test func aConversionIntoAFolderLandsThereNamedAfterTheSource() async throws {
        let image = try staging.add(.webp, as: "mountain-lake.webp")

        let result = try await Converter(downloads: downloads.url).convert(image, with: PNGAction(), into: destination.url)

        #expect(result.output == destination.url.appendingPathComponent("mountain-lake.png"))
        #expect(result.savedToDownloads == false)
        #expect(try ImageFacts(result.output).typeIdentifier == "public.png")
        #expect(try staging.fileNames() == ["mountain-lake.webp"])
        #expect(try downloads.fileNames() == [])
    }

    @Test func aNameTakenInTheFolderIsNumbered() async throws {
        let image = try staging.add(.webp, as: "mountain-lake.webp")
        try destination.add(.jpeg, as: "mountain-lake.jpg")

        let result = try await Converter(downloads: downloads.url).convert(image, with: JPEGAction(), into: destination.url)

        #expect(result.output == destination.url.appendingPathComponent("mountain-lake 2.jpg"))
        #expect(try Data(contentsOf: destination.url.appendingPathComponent("mountain-lake.jpg")) == Fixture.jpeg.data)
    }

    @Test func aFolderThatCantBeWrittenToSendsItToDownloads() async throws {
        let image = try staging.add(.webp, as: "mountain-lake.webp")
        try destination.makeReadOnly()

        let result = try await Converter(downloads: downloads.url).convert(image, with: PNGAction(), into: destination.url)

        #expect(result.output == downloads.url.appendingPathComponent("mountain-lake.png"))
        #expect(result.savedToDownloads == true)
        #expect(try destination.fileNames() == [])
    }

    @Test func aBatchIntoAFolderPutsEveryNewFileThere() async throws {
        let image = try staging.add(.webp, as: "mountain-lake.webp")

        let runner = JobRunner(converter: Converter(downloads: downloads.url))
        let batch = runner.run([image], to: [PNGAction()], into: destination.url)
        await batch.waitUntilFinished()

        #expect(batch.outputs == [destination.url.appendingPathComponent("mountain-lake.png")])
        #expect(try staging.fileNames() == ["mountain-lake.webp"])
    }

    // MARK: Original

    @Test(arguments: [(Fixture.webp, "sticker.webp"), (.jpeg, "photo.jpg"), (.png, "logo.png"), (.heicRotated, "IMG_1.heic")])
    func originalSavesTheImageAsItIsUnderItsOwnExtension(fixture: Fixture, name: String) async throws {
        let image = try staging.add(fixture, as: name)

        let result = try await Converter(downloads: downloads.url).convert(image, with: OriginalAction(), into: destination.url)

        #expect(result.output == destination.url.appendingPathComponent(name))
        #expect(result.format == .original)
        #expect(try Data(contentsOf: result.output) == fixture.data)
    }

    @Test func originalNumbersItsNameLikeAnyNewFile() async throws {
        let image = try staging.add(.webp, as: "sticker.webp")
        try destination.add(.webp, as: "sticker.webp")

        let result = try await Converter(downloads: downloads.url).convert(image, with: OriginalAction(), into: destination.url)

        #expect(result.output == destination.url.appendingPathComponent("sticker 2.webp"))
    }

    @Test func originalIsNotForVideosOrOtherFiles() async throws {
        let clip = try staging.add(.movH264, as: "clip.mov")
        let notes = try staging.add(.text, as: "notes.txt")

        await #expect(throws: ConversionError.notApplicable(clip, format: .original)) {
            try await Converter(downloads: downloads.url).convert(clip, with: OriginalAction(), into: destination.url)
        }
        await #expect(throws: ConversionError.self) {
            try await Converter(downloads: downloads.url).convert(notes, with: OriginalAction(), into: destination.url)
        }
        #expect(try destination.fileNames() == [])
    }

    // MARK: What is offered

    @Test func aStagedImageIsOfferedTheFormatsAndOriginalLast() async throws {
        let image = try staging.add(.webp, as: "mountain-lake.webp")

        let offers = try await offers(for: image)

        #expect(offers.targets.map(\.format) == [.png, .jpeg, .original])
        #expect(offers.targets.map(\.files) == [[image], [image], [image]])
    }

    @Test(arguments: [(Fixture.jpeg, OutputFormat.png), (.png, .jpeg)])
    func anImageAlreadyInAFormatIsOfferedTheOtherAndOriginal(fixture: Fixture, other: OutputFormat) async throws {
        let image = try staging.add(fixture)

        #expect(try await offers(for: image).targets.map(\.format) == [other, .original])
    }

    @Test func originalsSizeIsTheImagesOwnExactly() async throws {
        let image = try staging.add(.webp, as: "mountain-lake.webp")

        let original = try #require(try await offers(for: image).targets.last)

        #expect(original.estimate == .exactSize(Fixture.webp.data.count))
    }

    @Test(arguments: [(Fixture.webp, "WebP", 256, 192), (.jpeg, "JPEG", 256, 192), (.png, "PNG", 256, 192),
                      (.heicRotated, "HEIC", 192, 256)])
    func theOffersSayWhatTheImageIsUpright(fixture: Fixture, typeName: String, width: Int, height: Int) async throws {
        let image = try staging.add(fixture)

        let offers = try await offers(for: image)

        #expect(offers.original == Offers.Original(typeName: typeName, width: width, height: height))
    }

    @Test func filesOnDiskAreNeverOfferedOriginal() async throws {
        let image = try staging.add(.webp, as: "photo.webp")

        let live = await Estimator().estimate([image])
        await live.waitUntilFinished()

        #expect(live.offers.targets.map(\.format) == [.png, .jpeg])
        #expect(live.offers.original == nil)
        #expect(Offers(for: [image]).targets.map(\.format) == [.png, .jpeg])
    }

    @Test func somethingThatIsNotAnImageIsOfferedNothing() async throws {
        let notes = try staging.add(.text, as: "notes.txt")

        let offers = try await offers(for: notes)

        #expect(offers.targets.isEmpty)
        #expect(offers.reason != nil)
    }

    // MARK: Kept out of the command and the Finder menu

    @Test func originalIsNotAFormatFilesConvertTo() {
        #expect(OutputFormat.allCases == [.png, .jpeg, .mp4])
        #expect(OutputFormat(conversion: "original") == nil)
        #expect(OutputFormat(conversion: "png") == .png)
        #expect(OutputFormat.original.name == "Original")
    }

    /// The offers the ring gets for a staged image, once every estimate is in.
    private func offers(for image: URL) async throws -> Offers {
        let live = await Estimator().estimate([image], keepingOriginal: true)
        await live.waitUntilFinished()
        return live.offers
    }
}
