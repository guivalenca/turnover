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
        #expect(run.messages == [])
        #expect(try folder.fileNames() == ["photo.heic", "photo.png"])
    }

    @Test func anUnsupportedFileExitsNonZeroWithAShortReason() throws {
        let text = try folder.add(.text)

        let run = try turnover(text.path, "--to", "png")

        #expect(run.status == 1)
        #expect(run.output == "")
        #expect(run.messages == ["turnover: notes.txt: not an image or a video (text)"])
        #expect(try folder.fileNames() == ["notes.txt"])
    }

    @Test func aCorruptImageExitsNonZeroAndLeavesNothingBehind() throws {
        let broken = try folder.add(Fixture.heicRotated.data.prefix(2000), as: "broken.heic")

        let run = try turnover(broken.path, "--to", "png")

        #expect(run.status == 1)
        #expect(run.messages == ["turnover: broken.heic: damaged or incomplete, can't be decoded"])
        #expect(try folder.fileNames() == ["broken.heic"])
    }

    @Test func goodFilesStillConvertWhenAnotherFails() throws {
        let photo = try folder.add(.heicRotated, as: "photo.heic")
        let png = try folder.add(.png, as: "logo.png")

        let run = try turnover(png.path, photo.path, "--to", "png")

        #expect(run.status == 1)
        #expect(run.output == folder.url.appendingPathComponent("photo.png").path + "\n")
        #expect(run.messages == ["turnover: logo.png: already a PNG"])
    }

    @Test(arguments: [
        ["photo.heic"],
        ["photo.heic", "--to"],
        ["photo.heic", "--to", "gif"],
        ["--to", "png"],
        ["photo.heic", "--to", "png", "--fast"],
    ])
    func aBadCommandLineIsAUsageError(arguments: [String]) throws {
        try folder.add(.heicRotated, as: "photo.heic")

        let run = try turnover(arguments, in: folder.url)

        #expect(run.status == 64)
        #expect(run.errors.contains("usage: turnover"))
        #expect(try folder.fileNames() == ["photo.heic"])
    }

    @Test func relativePathsAreResolvedFromTheWorkingDirectory() throws {
        try folder.add(.heicRotated, as: "photo.heic")

        let run = try turnover(["photo.heic", "--to=png"], in: folder.url)

        #expect(run.status == 0)
        #expect(run.output.hasSuffix("/photo.png\n"))
        #expect(try folder.fileNames() == ["photo.heic", "photo.png"])
    }
}

// MARK: - Running the binary

struct Run {
    let status: Int32
    let output: String
    /// Everything on standard error. System frameworks may add noise here (on CI's virtual
    /// machines ImageIO logs a missing hardware scaler), so prefer `messages`.
    let errors: String

    /// The lines turnover itself wrote to standard error.
    var messages: [String] {
        errors.split(separator: "\n").map(String.init).filter { $0.hasPrefix("turnover: ") }
    }
}

/// Runs the `turnover` executable that `swift test` built next to this test bundle.
func turnover(_ arguments: String...) throws -> Run {
    try turnover(arguments)
}

func turnover(_ arguments: [String], in workingDirectory: URL? = nil) throws -> Run {
    let process = Process()
    process.executableURL = productsDirectory.appendingPathComponent("turnover")
    process.arguments = arguments
    process.currentDirectoryURL = workingDirectory
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
let productsDirectory = Bundle(for: BundleToken.self).bundleURL.deletingLastPathComponent()
