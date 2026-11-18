import Foundation
import Testing
import TurnoverKit
import TurnoverTestSupport

/// The URL the Finder extension opens to hand a conversion to the app, and how the app reads it.
@Suite struct ConversionRequests {
    let folder = try! ScratchFolder()

    @Test func aRequestTravelsAsATurnoverConvertURL() {
        let request = ConversionRequest(format: .png, files: [
            URL(fileURLWithPath: "/Users/me/IMG_0001.heic"),
            URL(fileURLWithPath: "/Volumes/Card/IMG_0002.heic"),
        ])

        #expect(request.url.absoluteString
            == "turnover://convert?to=png&file=/Users/me/IMG_0001.heic&file=/Volumes/Card/IMG_0002.heic")
    }

    @Test func theAppReadsBackTheFormatAndFilesWhateverTheirNames() throws {
        let files = try ["Tom & Jerry = 1+1 #2 100%.heic", "été?.mov", "plain.png"].map {
            try folder.add(.jpeg, as: $0)
        }
        let sent = ConversionRequest(format: .jpeg, files: files)

        let received = try ConversionRequest(sent.url)

        #expect(received == sent)
    }

    @Test func aFileListedTwiceIsConvertedOnce() throws {
        let photo = try folder.add(.heicRotated, as: "photo.heic")
        let movie = try folder.add(.movH264, as: "clip.mov")

        let request = try ConversionRequest(ConversionRequest(format: .png, files: [photo, movie, photo, photo]).url)

        #expect(request.files == [photo, movie])
    }

    /// Any process can open a `turnover:` URL, so the app takes only what the extension sends:
    /// a conversion to a known format of files that exist. `$FILE` is an existing photo, `$GONE`
    /// a missing one and `$FOLDER` a folder.
    @Test(arguments: [
        "https://convert?to=png&file=$FILE",
        "turnover://delete?to=png&file=$FILE",
        "turnover://convert/now?to=png&file=$FILE",
        "turnover://convert?to=gif&file=$FILE",
        "turnover://convert?file=$FILE",
        "turnover://convert?to=png&to=jpeg&file=$FILE",
        "turnover://convert?to=png&file=$FILE&then=delete",
        "turnover://convert?to=png",
        "turnover://convert?to=png&file=",
        "turnover://convert?to=png&file=Pictures/photo.heic",
        "turnover://convert?to=png&file=$GONE",
        "turnover://convert?to=png&file=$FILE&file=$GONE",
        "turnover://convert?to=png&file=$FOLDER",
    ])
    func anythingButConvertingExistingFilesToAKnownFormatIsRefused(template: String) throws {
        let photo = try folder.add(.heicRotated, as: "photo.heic")
        let url = URL(string: template
            .replacingOccurrences(of: "$FILE", with: photo.path)
            .replacingOccurrences(of: "$GONE", with: folder.url.appendingPathComponent("gone.heic").path)
            .replacingOccurrences(of: "$FOLDER", with: folder.url.path))!

        #expect(throws: ConversionRequest.Invalid.self) { try ConversionRequest(url) }
    }
}
