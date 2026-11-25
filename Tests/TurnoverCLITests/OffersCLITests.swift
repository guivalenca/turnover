import Foundation
import Testing
import TurnoverTestSupport

/// `turnover offers <files…>`, end to end.
@Suite struct OffersCLI {
    let folder = try! ScratchFolder()

    @Test func printsEachGroupsTargetsWithFileCountsAndEstimates() async throws {
        try folder.add(.heicRotated, as: "photo.heic")
        try folder.add(.png, as: "logo.png")
        try folder.add(.movH264, as: "clip.mov")
        try folder.add(.text)

        let run = try await turnover(["offers", "photo.heic", "logo.png", "clip.mov", "notes.txt"], in: folder.url)

        #expect(run.status == 0)
        #expect(run.messages == [])
        let lines = run.output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let expected = [
            #"Images \(2 files\)"#,
            // Small images are measured exactly at once, so their sizes have no "~".
            #"  PNG   1 file   ~?\d+ KB"#,
            #"  JPEG  2 files  Best ~?\d+ KB, High ~?\d+ KB \(default\), Small ~?\d+ KB"#,
            #"Videos \(1 file\)"#,
            #"  MP4   1 file   Instant"#,
            #"Skipped"#,
            #"  notes\.txt: not an image or a video \(text\)"#,
            "",
        ]
        #expect(lines.count == expected.count, "\(run.output)")
        for (line, pattern) in zip(lines, expected) {
            #expect(try Regex(pattern).wholeMatch(in: line) != nil, "\(line)")
        }
        // Nothing is converted.
        #expect(try folder.fileNames() == ["clip.mov", "logo.png", "notes.txt", "photo.heic"])
    }

    @Test func aVideoThatNeedsEncodingShowsAnApproximateTime() async throws {
        let movie = try folder.add(.movHEVCHDR, as: "clip.mov")

        let run = try await turnover("offers", movie.path)

        #expect(run.status == 0)
        #expect(run.output == "Videos (1 file)\n  MP4   1 file   About 1 s\n")
    }

    @Test func nothingToConvertListsWhyAndExitsNonZero() async throws {
        let pdf = try folder.add(.pdf)
        let text = try folder.add(.text)

        let run = try await turnover("offers", pdf.path, text.path)

        #expect(run.status == 1)
        #expect(run.output == """
            Skipped
              document.pdf: not an image or a video (PDF document)
              notes.txt: not an image or a video (text)

            """)
    }

    @Test func exactWaitsForTheMeasuredSizes() async throws {
        try folder.add(.heicRotated, as: "photo.heic")

        let run = try await turnover(["offers", "--exact", "photo.heic"], in: folder.url)

        #expect(run.status == 0)
        let lines = run.output.split(separator: "\n").map(String.init)
        let expected = [
            #"Images \(1 file\)"#,
            #"  PNG   1 file   \d+ KB"#,
            #"  JPEG  1 file   Best \d+ KB, High \d+ KB \(default\), Small \d+ KB"#,
        ]
        #expect(lines.count == expected.count, "\(run.output)")
        for (line, pattern) in zip(lines, expected) {
            #expect(try Regex(pattern).wholeMatch(in: line) != nil, "\(line)")
        }
    }

    @Test(arguments: [
        (["offers"], "no files given"),
        (["offers", "photo.heic", "--to", "png"], "unknown option --to"),
    ])
    func aBadCommandLineIsAUsageError(arguments: [String], message: String) async throws {
        try folder.add(.heicRotated, as: "photo.heic")

        let run = try await turnover(arguments, in: folder.url)

        #expect(run.status == 64)
        #expect(run.messages == ["turnover: \(message)"])
        #expect(run.errors.contains("usage: turnover offers [--exact] <files…>"))
    }

    @Test func theUsageListsTheOffersCommand() async throws {
        let run = try await turnover("--help")

        #expect(run.output.contains("turnover offers [--exact] <files…>"))
    }
}
