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
    }
}
