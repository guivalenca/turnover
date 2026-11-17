import UniformTypeIdentifiers

/// One image output whose size is estimated: PNG, or JPEG at one of its presets.
enum ImageOutput: Hashable, Sendable, CaseIterable {
    case png
    case jpeg(JPEGQuality)

    static let allCases: [ImageOutput] = [.png] + JPEGQuality.allCases.map(ImageOutput.jpeg)

    /// Nil for formats that aren't images (MP4).
    init?(_ format: OutputFormat, quality: JPEGQuality) {
        switch format {
        case .png: self = .png
        case .jpeg: self = .jpeg(quality)
        case .mp4: return nil
        }
    }

    var format: OutputFormat {
        switch self {
        case .png: .png
        case .jpeg: .jpeg
        }
    }

    var type: UTType { format == .png ? .png : .jpeg }

    /// The encoder quality, from 0 to 1, for JPEG; nil for PNG.
    var encoderQuality: Double? {
        if case .jpeg(let quality) = self { quality.encoderQuality } else { nil }
    }

    /// The outputs a conversion of `file` can produce: never the file's own format.
    static func of(_ file: SourceFile) -> [ImageOutput] {
        allCases.filter { $0.format.action().accepts(file) }
    }
}
