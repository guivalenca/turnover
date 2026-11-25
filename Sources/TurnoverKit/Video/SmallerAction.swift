import CoreMedia
import Foundation
import UniformTypeIdentifiers

/// Makes an MP4 smaller: the same video, re-encoded at a lower bit rate and, above the quality's
/// frame size, scaled down to it. The original stays; the new file goes next to it as `clip-s.mp4`.
///
/// Only MP4s: other videos are offered MP4.
public struct SmallerAction: ConversionAction {
    public var quality: VideoQuality

    public init(quality: VideoQuality = .default) {
        self.quality = quality
    }

    public var format: OutputFormat { .smaller }
    public var outputType: UTType { .mpeg4Movie }

    /// "clip-s", s for small. A file already named so keeps its name, and is numbered.
    public func baseName(for file: SourceFile) -> String {
        let own = file.url.deletingPathExtension().lastPathComponent
        return own.hasSuffix("-s") ? own : own + "-s"
    }

    public func accepts(_ file: SourceFile) -> Bool {
        file.kind == .video && file.contentType == .mpeg4Movie
    }

    public func perform(_ file: SourceFile, writingTo destination: URL) async throws {
        try await perform(file, writingTo: destination, progress: .ignored)
    }

    /// Throws `ConversionError.notSmaller` when the new file came out no smaller than the source:
    /// a video that is barely compressible any more (a still screen recording, say).
    public func perform(_ file: SourceFile, writingTo destination: URL, progress: ConversionProgress) async throws {
        try await MovieRewrite(file.url, to: destination, shrinkingTo: quality).run(progress: progress)
        if let before = Self.size(of: file.url), let after = Self.size(of: destination), after >= before {
            throw ConversionError.notSmaller(file.url)
        }
    }

    private static func size(of file: URL) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: file.path)[.size]) as? Int
    }
}

/// How much `SmallerAction` takes off a video. A higher quality gives a larger file.
///
/// The raw values ("high", "medium", "small") are what `turnover --quality` takes, so keep them
/// stable.
public enum VideoQuality: String, CaseIterable, Sendable {
    /// Up to 1080p.
    case high
    /// Up to 720p, the default.
    case medium
    /// Up to 480p.
    case small

    /// The quality used when none is chosen.
    public static let `default` = VideoQuality.medium

    /// The name users see: "High", "Medium" or "Small".
    public var name: String {
        switch self {
        case .high: String(localized: "High", bundle: .turnoverKit, comment: "A quality: JPEG at 85%, the default, or a smaller MP4 at up to 1080p.")
        case .medium: String(localized: "Medium", bundle: .turnoverKit, comment: "The quality of a smaller MP4 at up to 720p, the default.")
        case .small: String(localized: "Small", bundle: .turnoverKit, comment: "A quality: JPEG at 60%, or a smaller MP4 at up to 480p.")
        }
    }

    /// The most pixels the shorter side keeps: 1080, 720 or 480.
    public var shortSide: Int {
        switch self {
        case .high: 1080
        case .medium: 720
        case .small: 480
        }
    }

    /// Bits per pixel per frame, for a video that comes with plenty.
    var bitsPerPixel: Double {
        switch self {
        case .high: 0.10
        case .medium: 0.08
        case .small: 0.07
        }
    }

    /// The most of the source's own bit rate it keeps, so that a video that is already modest
    /// gets smaller too.
    var mostOfSource: Double {
        switch self {
        case .high: 0.6
        case .medium: 0.35
        case .small: 0.18
        }
    }
}

/// What making one video smaller gives: its frame size and bit rate.
struct SmallerPlan: Sendable, Hashable {
    /// The stored frame size, in square pixels, before the display matrix turns it.
    let width: Int
    let height: Int
    /// How much smaller than the source's the frame is: 1 for the same size.
    let scale: Double
    /// Bits per second.
    let bitRate: Double
    /// The new file's approximate size, in bytes.
    let bytes: Int

    init(_ movie: MovieSource, quality: VideoQuality) {
        let video = movie.video
        // As shown, pixel aspect ratio and clean aperture applied: the new pixels are square.
        let shown = video.format.presentationDimensions(usePixelAspectRatio: true, useCleanAperture: true)
        let scale = min(1, Double(quality.shortSide) / max(1, Double(min(shown.width, shown.height))))
        self.scale = scale
        // H.264 at 4:2:0 wants even sides.
        func even(_ side: CGFloat) -> Int { max(2, Int((Double(side) * scale / 2).rounded()) * 2) }
        let (width, height) = (even(shown.width), even(shown.height))
        (self.width, self.height) = (width, height)

        let frameRate = H264.frameRate(video.frameRate)
        var bitRate = Double(width * height) * frameRate * quality.bitsPerPixel
        if video.dataRate > 0 { bitRate = min(bitRate, video.dataRate * quality.mostOfSource) }
        self.bitRate = bitRate.rounded()

        let audioRate = movie.audio.map { AAC.isWidelyPlayable($0.format) ? $0.dataRate : 128_000 } ?? 0
        let seconds = movie.duration.seconds
        bytes = seconds.isFinite ? Int((bitRate + audioRate) * max(0, seconds) / 8) : 0
    }
}

extension CMFormatDescription {
    fileprivate func presentationDimensions(usePixelAspectRatio: Bool, useCleanAperture: Bool) -> CGSize {
        CMVideoFormatDescriptionGetPresentationDimensions(
            self, usePixelAspectRatio: usePixelAspectRatio, useCleanAperture: useCleanAperture)
    }
}
