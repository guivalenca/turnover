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
    }
}
