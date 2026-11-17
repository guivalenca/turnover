import Foundation
import Testing
import TurnoverKit
import TurnoverTestSupport

/// What `Converter.convert(_:with:progress:)` reports, whatever the action.
@Suite struct Progress {
    let folder = try! ScratchFolder()

    @Test func aQuickConversionReportsOnlyThatItIsDone() async throws {
        let photo = try folder.add(.heicRotated)
        let progress = ProgressRecorder()

        _ = try await Converter().convert(photo, with: PNGAction(), progress: progress.record)

        #expect(progress.values == [1])
    }

    @Test func aFailedConversionNeverReportsOne() async throws {
        let png = try folder.add(.png)
        let progress = ProgressRecorder()

        await #expect(throws: ConversionError.self) {
            try await Converter().convert(png, with: PNGAction(), progress: progress.record)
        }
        #expect(progress.values == [])
    }
}
