import Foundation
import Testing
import TurnoverAppCore
import UniformTypeIdentifiers

/// An image dragged out of a web page, told from what the drag pasteboard lists. The lists are
/// what each browser's own source puts there (Chromium's `web_drag_source_mac.mm`, WebKit's
/// `WebViewImpl::writePromisedImageDragDataToPasteboard`).
@Suite struct DraggedImageTests {
    let promise = "com.apple.pasteboard.promised-file-content-type"
    var chrome: [String] {
        ["org.chromium.chromium-initiated-drag", "org.chromium.chromium-renderer-initiated-drag", "public.url",
         "public.url-name", "org.webmproject.webp", "com.apple.pasteboard.promised-file-url", promise,
         "org.chromium.image-html"]
    }
    var safari: [String] {
        ["com.apple.NSFilePromiseItemMetaData", promise, "public.utf8-plain-text", "NSStringPboardType", "public.url",
         "public.url-name", "WebURLsWithTitlesPboardType", "public.jpeg", "public.tiff",
         "NeXT TIFF v4.0 pasteboard type", "com.apple.webarchive", "Apple Web Archive pasteboard type"]
    }

    // MARK: Which bytes

    @Test func chromeCarriesTheImageUnderItsOwnType() throws {
        let image = try #require(DraggedImage(types: chrome, promisedType: "org.webmproject.webp",
                                              url: "https://alpine-journal.example/photos/mountain-lake.webp"))

        #expect(image.pasteboardType == "org.webmproject.webp")
        #expect(image.contentType == .webP)
        #expect(image.fileName == "mountain-lake.webp")
    }

    @Test func safariCarriesTheOriginalNextToADecodedTIFF() throws {
        let image = try #require(DraggedImage(types: safari, promisedType: "public.jpeg",
                                              url: "https://alpine-journal.example/photos/dawn.jpeg"))

        #expect(image.pasteboardType == "public.jpeg")
        #expect(image.fileName == "dawn.jpg")
    }

    @Test func withoutAPromiseTheOriginalStillComesBeforeTheTIFF() throws {
        let image = try #require(DraggedImage(types: ["public.tiff", "public.png", "public.url"]))

        #expect(image.pasteboardType == "public.png")
    }

    @Test func aPictureOfferedOnlyAsTIFFIsATIFF() throws {
        let image = try #require(DraggedImage(types: ["public.utf8-plain-text", "public.tiff"]))

        #expect(image.contentType == .tiff)
        #expect(image.fileName == "image.tiff")
    }

    /// The promise names the type, but another type's bytes are all there is.
    @Test func aPromisedTypeWithoutItsBytesFallsBackToTheBytesThere() throws {
        let image = try #require(DraggedImage(types: [promise, "public.png"], promisedType: "public.heic"))

        #expect(image.pasteboardType == "public.png")
    }

    @Test(arguments: [
        ["public.file-url", "public.png"],                                              // a file, with its picture
        ["public.url", "public.url-name", "public.utf8-plain-text"],                    // a link
        ["public.utf8-plain-text", "public.rtf", "com.apple.webarchive"],                // selected text
        ["com.apple.NSFilePromiseItemMetaData", "com.apple.pasteboard.promised-file-content-type"],  // a promise alone
        ["com.adobe.pdf"],
        [],
    ])
    func anythingElseIsNotADraggedImage(types: [String]) {
        #expect(DraggedImage(types: types, promisedType: "public.heic") == nil)
    }

    // MARK: Its name

    @Test(arguments: [
        ("https://cdn.example/a/b/mountain-lake.webp?w=1600&fmt=webp", "mountain-lake"),
        ("https://cdn.example/photos/My%20photo.PNG", "My photo"),
        ("http://cdn.example/x/.hidden.gif", "hidden"),
    ])
    func anAddressThatNamesAnImageFileGivesTheName(url: String, name: String) {
        #expect(DraggedImage(types: chrome, url: url, title: "Something else")?.name == name)
    }

    /// An image inside a link is dragged with the link's address: a search result, say.
    @Test(arguments: [
        "https://www.search.example/imgres?q=mountain+lake&imgurl=x.jpg",
        "https://alpine-journal.example/posts/dawn",
        "https://alpine-journal.example/",
        "data:image/jpeg;base64,/9j/4AAQSkZJRg",
    ])
    func anyOtherAddressLeavesTheNameToTheTitle(url: String) {
        #expect(DraggedImage(types: chrome, url: url, title: "Mountain lake at dawn")?.name == "Mountain lake at dawn")
    }

    @Test(arguments: [
        ("  Lake:  dawn / dusk\n(2024)  ", "Lake dawn dusk (2024)"),
        ("...notes.", "notes"),
        (String(repeating: "word ", count: 40), String(String(repeating: "word ", count: 40).prefix(79))),
    ])
    func aTitleIsMadeSafeForAFileName(title: String, name: String) {
        #expect(DraggedImage(types: chrome, title: title)?.name == name)
    }

    @Test(arguments: [nil, "", "   ", "https://alpine-journal.example/dawn", "/:/"] as [String?])
    func withNothingToGoByItIsCalledImage(title: String?) {
        #expect(DraggedImage(types: chrome, title: title)?.fileName == "image.webp")
    }
}
