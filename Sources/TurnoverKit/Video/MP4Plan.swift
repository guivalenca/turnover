import CoreMedia
import Foundation

/// What converting one video to MP4 will involve, read from its tracks without decoding
/// anything. Offers use it to estimate how long the conversion takes.
public struct MP4Plan: Sendable, Hashable {
    /// The video is already H.264 that plays everywhere and is copied as is, so the conversion
    /// takes about as long as copying the file. (Audio that isn't AAC is still encoded, which
    /// is quick.) Otherwise the video is re-encoded, which takes time in proportion to
    /// `duration × frameWidth × frameHeight × frameRate`.
    public let passesVideoThrough: Bool
    /// In seconds.
    public let duration: Double
    /// The stored frame size, before the display matrix turns it (so a portrait iPhone video
    /// is wider than it is tall here).
    public let frameWidth: Int
    public let frameHeight: Int
    /// Frames per second.
    public let frameRate: Double

    init(_ movie: MovieSource) {
        passesVideoThrough = movie.video.isWidelyPlayable
        duration = movie.duration.seconds
        let size = movie.video.format.dimensions
        (frameWidth, frameHeight) = (Int(size.width), Int(size.height))
        frameRate = movie.video.frameRate
    }
}

extension MP4Action {
    /// Reads what converting `file` will involve: a few milliseconds per file. Throws
    /// `ConversionError.damaged` for a file the conversion would fail on as damaged, and
    /// `.notApplicable` for a movie without video.
    public func plan(for file: SourceFile) async throws -> MP4Plan {
        MP4Plan(try await MovieSource(file.url))
    }
}
