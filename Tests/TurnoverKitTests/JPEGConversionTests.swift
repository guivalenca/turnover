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
}
