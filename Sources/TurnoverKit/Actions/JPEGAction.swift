import Foundation
import UniformTypeIdentifiers

/// Converts any image to JPEG at one of the quality presets.
public struct JPEGAction: ConversionAction {
    public var quality: JPEGQuality

    public init(quality: JPEGQuality = .default) {
        self.quality = quality
    }

    public var format: OutputFormat { .jpeg }
    public var outputType: UTType { .jpeg }
    /// "jpg", the extension people expect, rather than UTType's preferred "jpeg".
    public var fileExtension: String { "jpg" }

    public func accepts(_ file: SourceFile) -> Bool {
        file.kind == .image && !file.contentType.conforms(to: .jpeg)
    }

    public func perform(_ file: SourceFile, writingTo destination: URL) async throws {
        // Off the concurrency threads, like PNG.
        let (source, type, encoderQuality) = (file.url, outputType, quality.encoderQuality)
        try await blocking(.userInitiated, throwing: {
            try ImageConversion.convert(source, to: destination, as: type, quality: encoderQuality)
        })
    }
}

/// How much a JPEG is compressed. A higher quality gives a larger file.
///
/// The raw values ("best", "high", "small") are what `turnover --quality` takes, and what the
/// app's settings should store, so keep them stable.
public enum JPEGQuality: String, CaseIterable, Sendable {
    /// 100%.
    case best
    /// 85%, the default.
    case high
    /// 60%.
    case small

    /// The preset used when none is chosen.
    public static let `default` = JPEGQuality.high

    /// The name users see: "Best", "High" or "Small".
    public var name: String {
        switch self {
        case .best: String(localized: "Best", bundle: .turnoverKit, comment: "The JPEG quality of 100%.")
        case .high: String(localized: "High", bundle: .turnoverKit, comment: "A quality: JPEG at 85%, the default, or a smaller MP4 at up to 1080p.")
        case .small: String(localized: "Small", bundle: .turnoverKit, comment: "A quality: JPEG at 60%, or a smaller MP4 at up to 480p.")
        }
    }

    /// The encoder quality as a percentage: 100, 85 or 60.
    public var percent: Int {
        switch self {
        case .best: 100
        case .high: 85
        case .small: 60
        }
    }

    /// `percent` as ImageIO takes it, from 0 to 1.
    var encoderQuality: Double { Double(percent) / 100 }
}
