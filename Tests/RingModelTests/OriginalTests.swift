import Foundation
import RingModel
import Testing
import TurnoverKit

/// An image dragged out of a web page: the ring offers the formats and Original, which saves
/// it as it is, and its centre says what the image is.
@Suite struct WebImage {
    // MARK: Where the entries sit

    @Test func originalSitsAtTheBottomWithPNGAndJPEGAboveIt() {
        let ring = RingModel.opened(with: Sample.webImage())

        #expect(ring.entries.map(\.title) == ["PNG", "JPEG", "Original"])
        #expect(ring.entries.map(\.angle) == [-150, -30, 90])
    }

    @Test(arguments: [("JPEG", OutputFormat.png), ("PNG", .jpeg)])
    func anImageAlreadyInAFormatHasTheOtherAtTheTop(typeName: String, other: OutputFormat) {
        let ring = RingModel.opened(with: Sample.webImage(typeName: typeName, formats: [other]))

        #expect(ring.entries.map(\.title) == [other.name, "Original"])
        #expect(ring.entries.map(\.angle) == [-90, 90])
    }

    @Test(arguments: [(-150.0, "PNG"), (170, "PNG"), (-95, "PNG"), (-85, "JPEG"), (-30, "JPEG"), (25, "JPEG"),
                      (35, "Original"), (90, "Original"), (145, "Original")])
    func eachEntryOwnsAThirdOfTheRing(degrees: Double, expected: String) {
        var ring = RingModel.opened(with: Sample.webImage())

        ring.send(.pointer(at: degrees, distance: 100))

        #expect(ring.highlighted?.title == expected)
    }

    @Test func optionFansJPEGOutAroundWhereItWas() {
        var ring = RingModel.opened(with: Sample.webImage())

        ring.send(.option(down: true))

        #expect(ring.entries.map(\.title) == ["PNG", "Best", "High", "Small", "Original"])
        #expect(ring.entries.map(\.angle) == [-150, -84, -30, 24, 90])
    }

    @Test func optionFansALoneJPEGOutAroundTheTop() {
        var ring = RingModel.opened(with: Sample.webImage(typeName: "PNG", formats: [.jpeg]))

        ring.send(.option(down: true))

        #expect(ring.entries.map(\.title) == ["Best", "High", "Small", "Original"])
        #expect(ring.entries.map(\.angle) == [-144, -90, -36, 90])
    }

    // MARK: What the ring says

    @Test func originalNamesTheImagesOwnFormatBeforeItsSize() {
        let ring = RingModel.opened(with: Sample.webImage(png: .size(3_100_000), jpeg: .size(480_000)))

        #expect(ring.entries.map(\.subtitle) == ["~3.1 MB", "~480 KB", "WebP · 212 KB"])
    }

    @Test func sizesNotKnownYetShowAsEllipses() {
        let ring = RingModel.opened(with: Sample.webImage(original: nil))

        #expect(ring.entries.map(\.subtitle) == ["…", "…", "WebP · …"])
    }

    @Test func theHubSaysWhatTheImageIsUntilAnEntryIsPointedAt() {
        let ring = RingModel.opened(with: Sample.webImage())

        #expect(ring.hub?.title == "WebP")
        #expect(ring.hub?.detail == "1600 × 1067")
        #expect(ring.hub?.text == "WebP · 1600 × 1067")
    }

    @Test func anImageWhoseSizeCantBeReadIsJustAnImage() {
        let ring = RingModel.opened(with: Sample.webImage(width: nil, height: nil))

        #expect(ring.hub?.title == "WebP")
        #expect(ring.hub?.detail == "image")
    }

    @Test func overOriginalTheHubKeepsTheFormatAndGivesItsSize() {
        var ring = RingModel.opened(with: Sample.webImage())

        ring.send(.pointer(at: 90, distance: 100))

        #expect(ring.hub?.title == "WebP")
        #expect(ring.hub?.detail == "212 KB")
    }

    @Test func overAFormatTheHubSaysWhatADropConvertsTo() {
        var ring = RingModel.opened(with: Sample.webImage(png: .size(3_100_000)))

        ring.send(.pointer(at: -150, distance: 100))

        #expect(ring.hub?.title == "PNG")
        #expect(ring.hub?.detail == "~3.1 MB")
    }

    @Test func oneImageNeverAsksToRestOnAFormat() {
        var ring = RingModel.opened(with: Sample.webImage())

        ring.send(.time(10))
        ring.send(.pointer(at: 90, distance: 100))
        ring.send(.time(20))

        #expect(ring.caption == nil)
        #expect(ring.rest == nil)
        #expect(ring.added.isEmpty)
    }

    // MARK: Dropping

    @Test func aDropOnOriginalSavesTheImageAsItIs() {
        var ring = RingModel.opened(with: Sample.webImage())

        ring.send(.pointer(at: 90, distance: 100))
        ring.send(.drop)

        #expect(ring.outcome == .convert([.init(kind: .image, format: .original, files: [Sample.webImage])]))
        #expect(ring.phase == .idle)
    }

    @Test func aDropOnAFormatConvertsTheImage() {
        var ring = RingModel.opened(with: Sample.webImage())

        ring.send(.pointer(at: -150, distance: 100))
        ring.send(.drop)

        #expect(ring.outcome == .convert([.init(kind: .image, format: .png, files: [Sample.webImage])]))
    }

    @Test func aDropOnAFannedOutQualitySavesAJPEGAtIt() {
        var ring = RingModel.opened(with: Sample.webImage())

        ring.send(.option(down: true))
        ring.send(.pointer(at: 24, distance: 100))
        ring.send(.drop)

        #expect(ring.outcome == .convert([.init(kind: .image, format: .jpeg, quality: .jpeg(.small), files: [Sample.webImage])]))
    }

    @Test func aDropOnTheHubCancels() {
        var ring = RingModel.opened(with: Sample.webImage())

        ring.send(.drop)

        #expect(ring.outcome == .cancel)
    }
}
