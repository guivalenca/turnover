import Foundation
import Testing
import TurnoverTestSupport

/// `turnover offers <files…>`, end to end.
@Suite struct OffersCLI {
    let folder = try! ScratchFolder()

    @Test func printsEachGroupsTargetsWithFileCountsAndEstimates() throws {
        try folder.add(.heicRotated, as: "photo.heic")
        try folder.add(.png, as: "logo.png")
        try folder.add(.movH264, as: "clip.mov")
        try folder.add(.text)

        let run = try turnover(["offers", "photo.heic", "logo.png", "clip.mov", "notes.txt"], in: folder.url)

        #expect(run.status == 0)
        #expect(run.messages == [])
        let lines = run.output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let expected = [
            #"Images \(2 files\)"#,
            #"  PNG   1 file   ~\d+ KB"#,
            #"  JPEG  2 files  Best ~\d+ KB, High ~\d+ KB \(default\), Small ~\d+ KB"#,
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

    @Test func aVideoThatNeedsEncodingShowsAnApproximateTime() throws {
        let movie = try folder.add(.movHEVCHDR, as: "clip.mov")

        let run = try turnover("offers", movie.path)

        #expect(run.status == 0)
        #expect(run.output == "Videos (1 file)\n  MP4   1 file   About 1 s\n")
    }

    @Test func nothingToConvertListsWhyAndExitsNonZero() throws {
        let pdf = try folder.add(.pdf)
        let mp4 = try folder.add(.mp4H264, as: "clip.mp4")

        let run = try turnover("offers", pdf.path, mp4.path)

        #expect(run.status == 1)
        #expect(run.output == """
            Skipped
              document.pdf: not an image or a video (PDF document)
              clip.mp4: already an MP4

            """)
    }

    @Test(arguments: [
        (["offers"], "no files given"),
        (["offers", "photo.heic", "--to", "png"], "unknown option --to"),
    ])
    func aBadCommandLineIsAUsageError(arguments: [String], message: String) throws {
        try folder.add(.heicRotated, as: "photo.heic")

        let run = try turnover(arguments, in: folder.url)

        #expect(run.status == 64)
        #expect(run.messages == ["turnover: \(message)"])
        #expect(run.errors.contains("usage: turnover offers <files…>"))
    }

    @Test func theUsageListsTheOffersCommand() throws {
        let run = try turnover("--help")

        #expect(run.output.contains("turnover offers <files…>"))
    }
}
