import Foundation
import UniformTypeIdentifiers

/// Converts any image to JPEG at one of the quality presets.
public struct JPEGAction: ConversionAction {
    public var quality: JPEGQuality

    public init(quality: JPEGQuality = .default) {
        self.quality = quality
    }

    public var name: String { "JPEG" }
    public var outputType: UTType { .jpeg }
    /// "jpg", the extension people expect, rather than UTType's preferred "jpeg".
    public var fileExtension: String { "jpg" }

    public func accepts(_ file: SourceFile) -> Bool {
        file.kind == .image && !file.contentType.conforms(to: .jpeg)
    }

    public func perform(_ file: SourceFile, writingTo destination: URL) async throws {
        try ImageConversion.convert(file.url, to: destination, as: outputType, quality: Double(quality.percent) / 100)
    }
}

/// How much a JPEG is compressed. A higher quality gives a larger file.
///
/// The raw values ("best", "high", "small") are what `turnover --quality` takes and what the
/// settings store, so keep them stable.
public enum JPEGQuality: String, CaseIterable, Sendable {
    /// 100%.
    case best
    /// 85%, the default.
    case high
    /// 60%.
    case small

    /// The preset used when none is chosen.
    public static let `default` = JPEGQuality.high

    /// The encoder quality as a percentage: 100, 85 or 60.
    public var percent: Int {
        switch self {
        case .best: 100
        case .high: 85
        case .small: 60
        }
    }
}
