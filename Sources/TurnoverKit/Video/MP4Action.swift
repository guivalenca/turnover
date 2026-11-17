import Foundation
import UniformTypeIdentifiers

/// Converts a video to an MP4 that plays everywhere: H.264 video and AAC audio.
///
/// Video that is already widely playable H.264 is copied into the new container untouched, which
/// takes about as long as copying the file. Anything else is re-encoded at the source's frame size
/// and frame rate.
public struct MP4Action: ConversionAction {
    public init() {}

    public var name: String { "MP4" }
    public var outputType: UTType { .mpeg4Movie }

    /// Any movie but an MPEG-4 one. M4V files are MPEG-4 underneath but still offered MP4: that is
    /// how to get a `.mp4` out of Finder's "Encode Selected Video Files".
    public func accepts(_ file: SourceFile) -> Bool {
        file.kind == .video && file.contentType != .mpeg4Movie
    }

    public func perform(_ file: SourceFile, writingTo destination: URL) async throws {
        try await MovieRewrite(file.url, to: destination).run()
    }
}
