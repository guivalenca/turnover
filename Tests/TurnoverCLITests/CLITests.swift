import Foundation
import Testing
import TurnoverTestSupport

/// End-to-end smoke tests: run the built `turnover` binary on real files.
@Suite struct CLI {
    let folder = try! ScratchFolder()

    @Test func convertsAPhotoToPNGAndPrintsItsPath() throws {
        let photo = try folder.add(.heicRotated, as: "photo.heic")

        let run = try turnover(photo.path, "--to", "png")

        #expect(run.status == 0)
        #expect(run.output == folder.url.appendingPathComponent("photo.png").path + "\n")
        #expect(run.errors == "")
        #expect(try folder.fileNames() == ["photo.heic", "photo.png"])
    }
}

// MARK: - Running the binary

struct Run {
    let status: Int32
    let output: String
    let errors: String
}

/// Runs the `turnover` executable that `swift test` built next to this test bundle.
func turnover(_ arguments: String...) throws -> Run {
    let process = Process()
    process.executableURL = productsDirectory.appendingPathComponent("turnover")
    process.arguments = arguments
    let output = Pipe(), errors = Pipe()
    process.standardOutput = output
    process.standardError = errors
    try process.run()
    let out = output.fileHandleForReading.readDataToEndOfFile()
    let err = errors.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return Run(status: process.terminationStatus,
               output: String(decoding: out, as: UTF8.self),
               errors: String(decoding: err, as: UTF8.self))
}

private final class BundleToken {}

/// The build products folder, where the test bundle and the `turnover` binary both live.
private let productsDirectory = Bundle(for: BundleToken.self).bundleURL.deletingLastPathComponent()
