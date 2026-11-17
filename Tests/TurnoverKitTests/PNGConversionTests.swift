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
}
