/// A quality to convert at, for the formats that have them: JPEG and a smaller MP4.
public enum Quality: Sendable, Hashable {
    case jpeg(JPEGQuality)
    case video(VideoQuality)

    /// The name users see: "Best", "Medium", ….
    public var name: String {
        switch self {
        case .jpeg(let quality): quality.name
        case .video(let quality): quality.name
        }
    }
}

extension OutputFormat {
    /// The qualities it comes in, from the largest file to the smallest; empty for formats
    /// without any.
    public var qualities: [Quality] {
        switch self {
        case .jpeg: JPEGQuality.allCases.map(Quality.jpeg)
        case .smaller: VideoQuality.allCases.map(Quality.video)
        case .png, .mp4, .original: []
        }
    }
}
