import Foundation
import Testing
import TurnoverKit
import TurnoverTestSupport

/// Which formats are offered for a selection, and which files each one applies to.
@Suite struct WhatIsOffered {
    let folder = try! ScratchFolder()

    @Test func aHEICOffersPNGAndJPEG() throws {
        let photo = try folder.add(.heicRotated, as: "photo.heic")

        let offers = Offers(for: [photo])

        #expect(offers.groups.map(\.kind) == [.image])
        #expect(offers.targets.map(\.format) == [.png, .jpeg])
        #expect(offers.targets.map(\.files) == [[photo], [photo]])
    }

    @Test(arguments: [(Fixture.png, OutputFormat.jpeg), (.jpeg, .png)])
    func anImageIsNotOfferedItsOwnFormat(fixture: Fixture, offered: OutputFormat) throws {
        let image = try folder.add(fixture)

        #expect(Offers(for: [image]).targets.map(\.format) == [offered])
    }

    @Test func eachFormatAppliesOnlyToTheImagesNotAlreadyInIt() throws {
        let png = try folder.add(.png, as: "logo.png")
        let jpeg = try folder.add(.jpeg, as: "photo.jpg")

        let offers = Offers(for: [png, jpeg])

        #expect(offers.groups.map(\.files) == [[png, jpeg]])
        #expect(offers.targets.map(\.format) == [.png, .jpeg])
        #expect(offers.targets.map(\.files) == [[jpeg], [png]])
    }

    @Test func aQuickTimeMovieOffersMP4() throws {
        let movie = try folder.add(.movHEVCHDR, as: "clip.mov")

        let offers = Offers(for: [movie])

        #expect(offers.groups.map(\.kind) == [.video])
        #expect(offers.targets.map(\.format) == [.mp4])
        #expect(offers.targets.map(\.files) == [[movie]])
    }

    @Test func imagesAndVideosTogetherMakeTwoGroupsImagesFirst() throws {
        let movie = try folder.add(.movH264, as: "clip.mov")
        let photo = try folder.add(.heicRotated, as: "photo.heic")
        let webp = try folder.add(.webp, as: "sticker.webp")

        let offers = Offers(for: [movie, photo, webp])

        #expect(offers.groups.map(\.kind) == [.image, .video])
        #expect(offers.groups.map(\.files) == [[photo, webp], [movie]])
        #expect(offers.targets.map(\.format) == [.png, .jpeg, .mp4])
        #expect(offers.skipped == [])
        #expect(offers.reason == nil)
    }
}

/// MP4s have nothing to convert to but a smaller MP4.
@Suite struct WhatAnMP4Offers {
    let folder = try! ScratchFolder()

    @Test func onlyASmallerOne() throws {
        let movie = try folder.add(.mp4H264, as: "clip.mp4")

        let offers = Offers(for: [movie])

        #expect(offers.targets.map(\.format) == [.smaller])
        #expect(offers.targets.first?.files == [movie])
        #expect(offers.targets.first?.menuTitle == "Smaller MP4 (1 video)")
        #expect(offers.skipped == [])
    }
}

/// Files nothing is offered for, and the hint shown when that is the whole selection.
@Suite struct WhatIsSkipped {
    let folder = try! ScratchFolder()

    @Test(arguments: [(Fixture.pdf, "PDF document"), (.text, "text")])
    func aDocumentIsUnsupportedAndTheReasonNamesItsType(fixture: Fixture, type: String) throws {
        let document = try folder.add(fixture)

        let offers = Offers(for: [document])

        #expect(offers.targets == [])
        #expect(offers.skipped == [.unsupported(document, typeDescription: type)])
        #expect(offers.reason == "\(fixture.rawValue): not an image or a video (\(type))")
    }

    @Test func severalUnconvertibleFilesAreAllReportedAndTheReasonCountsTheRest() throws {
        let pdf = try folder.add(.pdf)
        let text = try folder.add(.text)
        let missing = folder.url.appendingPathComponent("gone.heic")

        let offers = Offers(for: [pdf, text, missing])

        #expect(offers.targets == [])
        #expect(offers.skipped == [
            .unsupported(pdf, typeDescription: "PDF document"),
            .unsupported(text, typeDescription: "text"),
            .unreadable(missing),
        ])
        #expect(offers.reason == "document.pdf: not an image or a video (PDF document), and 2 more files")
    }

    @Test func oneMoreFileIsSingular() throws {
        let pdf = try folder.add(.pdf)
        let text = try folder.add(.text)

        #expect(Offers(for: [pdf, text]).reason == "document.pdf: not an image or a video (PDF document), and 1 more file")
    }

    @Test func unsupportedFilesNextToConvertibleOnesAreReportedWithoutAReason() throws {
        let photo = try folder.add(.heicRotated, as: "photo.heic")
        let movie = try folder.add(.movH264, as: "clip.mov")
        let mp4 = try folder.add(.mp4H264, as: "done.mp4")
        let pdf = try folder.add(.pdf)

        let offers = Offers(for: [photo, pdf, movie, mp4])

        #expect(offers.targets.map(\.format) == [.png, .jpeg, .mp4, .smaller])
        #expect(offers.groups.map(\.files) == [[photo], [movie, mp4]])
        #expect(offers.targets.map(\.files) == [[photo], [photo], [movie], [mp4]])
        #expect(offers.skipped == [.unsupported(pdf, typeDescription: "PDF document")])
        #expect(offers.reason == nil)
    }

    @Test func anEmptySelectionOffersNothing() {
        let offers = Offers(for: [])

        #expect(offers.targets == [])
        #expect(offers.reason == "No files")
    }
}
