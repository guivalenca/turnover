import Foundation
import Testing
import TurnoverKit
import TurnoverTestSupport

@Suite struct JPEGConversion {
    let folder = try! ScratchFolder()

    @Test func heicBecomesJPGNextToTheOriginal() async throws {
        let photo = try folder.add(.heicRotated, as: "photo.heic")

        let result = try await Converter().convert(photo, with: JPEGAction())

        #expect(result.output == folder.url.appendingPathComponent("photo.jpg"))
        #expect(try ImageFacts(result.output).typeIdentifier == "public.jpeg")
        #expect(try folder.fileNames() == ["photo.heic", "photo.jpg"])
        #expect(try Data(contentsOf: photo) == Fixture.heicRotated.data)
    }

    @Test func theDefaultQualityIsHigh85Percent() async throws {
        let photo = try folder.add(.heicRotated)

        let output = try await Converter().convert(photo, with: JPEGAction()).output

        #expect(try JPEGTables(output) == JPEGTables(quality: 0.85))
    }

    @Test(arguments: [(JPEGQuality.best, 1.0), (.high, 0.85), (.small, 0.6)])
    func eachPresetEncodesAtItsPercentage(preset: JPEGQuality, quality: Double) async throws {
        let photo = try folder.add(.heicRotated)

        let output = try await Converter().convert(photo, with: JPEGAction(quality: preset)).output

        #expect(try JPEGTables(output) == JPEGTables(quality: quality))
    }

    @Test func higherQualityGivesALargerFile() async throws {
        let photo = try folder.add(.heicRotated)

        var sizes: [JPEGQuality: Int] = [:]
        for preset in JPEGQuality.allCases {
            let output = try await Converter().convert(photo, with: JPEGAction(quality: preset)).output
            sizes[preset] = try Data(contentsOf: output).count
        }

        #expect(sizes[.best]! > sizes[.high]!)
        #expect(sizes[.high]! > sizes[.small]!)
    }

    @Test(arguments: [Fixture.png, .webp])
    func otherImageFormatsConvertToo(fixture: Fixture) async throws {
        let image = try folder.add(fixture)

        let jpeg = try ImageFacts(try await Converter().convert(image, with: JPEGAction()).output)

        #expect(jpeg.typeIdentifier == "public.jpeg")
        #expect((jpeg.width, jpeg.height) == (256, 192))
        #expect(jpeg.isMarkerRed(x: 8, y: 8))
    }

    @Test func transparentAreasBecomeWhite() async throws {
        // Below the opaque red marker, the left edge of transparent.png is fully clear.
        let png = try folder.add(.png)

        let jpeg = try ImageFacts(try await Converter().convert(png, with: JPEGAction()).output)

        let clear = jpeg.pixel(x: 8, y: 100)
        #expect(clear.red > 250 && clear.green > 250 && clear.blue > 250)
        #expect(jpeg.isMarkerRed(x: 8, y: 8))
    }

    // The guarantees PNG gives, checked at the lowest quality.

    @Test func aRotatedPhotoComesOutUpright() async throws {
        // Stored 256×192 with orientation 6; upright it is 192×256 with red in the top-left corner.
        let photo = try folder.add(.heicRotated)

        let jpeg = try ImageFacts(try await Converter().convert(photo, with: JPEGAction(quality: .small)).output)

        #expect((jpeg.width, jpeg.height) == (192, 256))
        #expect(jpeg.orientation == 1)
        #expect(jpeg.isMarkerRed(x: 8, y: 8))
        #expect(!jpeg.isMarkerRed(x: 183, y: 8))
        #expect(!jpeg.isMarkerRed(x: 8, y: 247))
    }

    @Test func colourProfileAndMetadataAreKept() async throws {
        let photo = try folder.add(.heicRotated)

        let jpeg = try ImageFacts(try await Converter().convert(photo, with: JPEGAction(quality: .small)).output)

        #expect(jpeg.profileName == "Display P3")
        #expect(jpeg.exif["DateTimeOriginal"] as? String == "2024:06:15 10:30:00")
        #expect(jpeg.exif["LensModel"] as? String == "Fixture Lens 4.2mm f/1.8")
        #expect(jpeg.tiff["Make"] as? String == "Turnover")
        #expect(jpeg.tiff["Model"] as? String == "Fixture Camera")
        #expect(jpeg.gps["Latitude"] as? Double == 48.8584)
        #expect(jpeg.gps["LatitudeRef"] as? String == "N")
        #expect(jpeg.gps["Longitude"] as? Double == 2.2945)
        #expect(jpeg.gps["LongitudeRef"] as? String == "E")
        #expect(jpeg.gps["Altitude"] as? Double == 35)
    }

    @Test func outputKeepsTheOriginalsCreationAndModificationDates() async throws {
        let photo = try folder.add(.heicRotated)
        let created = Date(timeIntervalSince1970: 1_718_447_400)  // 2024-06-15 10:30:00 UTC
        let modified = Date(timeIntervalSince1970: 1_718_620_200)  // 2024-06-17 10:30:00 UTC
        try FileManager.default.setAttributes([.creationDate: created, .modificationDate: modified], ofItemAtPath: photo.path)

        let output = try await Converter().convert(photo, with: JPEGAction(quality: .small)).output

        let dates = try output.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        #expect(dates.creationDate == created)
        #expect(dates.contentModificationDate == modified)
    }

    @Test func existingNamesGetAFinderStyleNumberAndAreNeverOverwritten() async throws {
        let photo = try folder.add(.heicRotated, as: "IMG_0001.heic")
        let existing = try folder.add(Data("already here".utf8), as: "IMG_0001.jpg")

        let second = try await Converter().convert(photo, with: JPEGAction(quality: .small))
        let third = try await Converter().convert(photo, with: JPEGAction(quality: .best))

        #expect(second.output.lastPathComponent == "IMG_0001 2.jpg")
        #expect(third.output.lastPathComponent == "IMG_0001 3.jpg")
        #expect(try Data(contentsOf: existing) == Data("already here".utf8))
        #expect(try JPEGTables(third.output) == JPEGTables(quality: 1))
    }

    @Test func aJPEGIsNotConvertedToJPEG() async throws {
        let jpeg = try folder.add(.jpeg, as: "photo.jpg")

        await #expect(throws: ConversionError.alreadyInFormat(jpeg, format: .jpeg)) {
            try await Converter().convert(jpeg, with: JPEGAction())
        }
        #expect(try folder.fileNames() == ["photo.jpg"])
    }
}
