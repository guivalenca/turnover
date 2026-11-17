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

    @Test func aJPEGIsNotConvertedToJPEG() async throws {
        let jpeg = try folder.add(.jpeg, as: "photo.jpg")

        await #expect(throws: ConversionError.alreadyInFormat(jpeg, format: "JPEG")) {
            try await Converter().convert(jpeg, with: JPEGAction())
        }
        #expect(try folder.fileNames() == ["photo.jpg"])
    }
}
