import Foundation
import Testing
import TurnoverKit
import TurnoverTestSupport

@Suite struct PNGConversion {
    let folder = try! ScratchFolder()

    @Test func heicBecomesPNGNextToTheOriginal() async throws {
        let photo = try folder.add(.heicRotated, as: "photo.heic")

        let result = try await Converter().convert(photo, with: PNGAction())

        #expect(result.output == folder.url.appendingPathComponent("photo.png"))
        #expect(try ImageFacts(result.output).typeIdentifier == "public.png")
        #expect(try folder.fileNames() == ["photo.heic", "photo.png"])
        #expect(try Data(contentsOf: photo) == Fixture.heicRotated.data)
    }

    @Test func existingNamesGetAFinderStyleNumberAndAreNeverOverwritten() async throws {
        let photo = try folder.add(.heicRotated, as: "photo.heic")
        let existing = try folder.add(Data("already here".utf8), as: "photo.png")

        let second = try await Converter().convert(photo, with: PNGAction())
        let third = try await Converter().convert(photo, with: PNGAction())

        #expect(second.output.lastPathComponent == "photo 2.png")
        #expect(third.output.lastPathComponent == "photo 3.png")
        #expect(try Data(contentsOf: existing) == Data("already here".utf8))
        #expect(try ImageFacts(second.output).typeIdentifier == "public.png")
        #expect(try folder.fileNames() == ["photo 2.png", "photo 3.png", "photo.heic", "photo.png"])
    }

    @Test func aRotatedPhotoComesOutUpright() async throws {
        // Stored 256×192 with orientation 6; upright it is 192×256 with red in the top-left corner.
        let photo = try folder.add(.heicRotated)

        let png = try ImageFacts(try await Converter().convert(photo, with: PNGAction()).output)

        #expect((png.width, png.height) == (192, 256))
        #expect(png.orientation == 1)
        #expect(png.isMarkerRed(x: 8, y: 8))
        #expect(!png.isMarkerRed(x: 183, y: 8))
        #expect(!png.isMarkerRed(x: 8, y: 247))
    }

    @Test func colourProfileAndMetadataAreKept() async throws {
        let photo = try folder.add(.heicRotated)

        let png = try ImageFacts(try await Converter().convert(photo, with: PNGAction()).output)

        #expect(png.profileName == "Display P3")
        #expect(png.exif["DateTimeOriginal"] as? String == "2024:06:15 10:30:00")
        #expect(png.exif["LensModel"] as? String == "Fixture Lens 4.2mm f/1.8")
        #expect(png.tiff["Make"] as? String == "Turnover")
        #expect(png.tiff["Model"] as? String == "Fixture Camera")
        #expect(png.gps["Latitude"] as? Double == 48.8584)
        #expect(png.gps["LatitudeRef"] as? String == "N")
        #expect(png.gps["Longitude"] as? Double == 2.2945)
        #expect(png.gps["LongitudeRef"] as? String == "E")
        #expect(png.gps["Altitude"] as? Double == 35)
    }
}
