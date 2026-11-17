import Foundation
import Testing
import TurnoverKit
import TurnoverTestSupport

/// Inputs a conversion must refuse or fail on, always leaving the folder as it was.
@Suite struct Refusals {
    let folder = try! ScratchFolder()

    @Test func aPNGIsNotConvertedToPNG() async throws {
        let png = try folder.add(.png, as: "logo.png")

        await #expect(throws: ConversionError.alreadyInFormat(png, format: "PNG")) {
            try await Converter().convert(png, with: PNGAction())
        }
        #expect(try folder.fileNames() == ["logo.png"])
    }
}
