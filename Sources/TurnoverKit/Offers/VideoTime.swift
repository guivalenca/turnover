import Foundation

/// Roughly how long converting one video to MP4 takes, from its plan, and for a video that is an
/// MP4 already, how big making it smaller leaves it.
///
/// Calibrated on an Apple Silicon Mac with the hardware H.264 encoder (see the #5 notes): copying
/// the video into the new container runs at about 275 MB/s of file, and re-encoding at about
/// 550 million pixels per second.
struct VideoTime: Sendable {
    /// In seconds.
    let seconds: Double
    /// Whether the video is only copied, not re-encoded.
    let isCopy: Bool
    /// For an MP4, the approximate size at each quality, in bytes; empty for other videos.
    let smaller: [VideoQuality: Int]

    static let copiedBytesPerSecond = 275e6
    static let encodedPixelsPerSecond = 550e6

    /// Nil when the video can't be planned (it is damaged, or has no video track).
    init?(of file: SourceFile) async {
        guard let movie = try? await MovieSource(file.url) else { return nil }
        let plan = MP4Plan(movie)
        smaller = !SmallerAction().accepts(file) ? [:] : Dictionary(uniqueKeysWithValues: VideoQuality.allCases.map {
            ($0, SmallerPlan(movie, quality: $0).bytes)
        })
        isCopy = plan.passesVideoThrough
        if isCopy {
            let bytes = (try? file.url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            seconds = Double(bytes) / Self.copiedBytesPerSecond
        } else {
            let pixels = Double(plan.frameWidth * plan.frameHeight) * plan.frameRate * plan.duration
            seconds = pixels / Self.encodedPixelsPerSecond
        }
    }

    /// The times of every video in `videos` that can be planned, worked out side by side.
    static func of(_ videos: [SourceFile]) async -> [URL: VideoTime] {
        await withTaskGroup(of: (URL, VideoTime?).self) { group in
            for video in videos { group.addTask { (video.url, await VideoTime(of: video)) } }
            return await group.reduce(into: [URL: VideoTime]()) { $0[$1.0] = $1.1 }
        }
    }

    /// The estimate for converting `videos` as one batch: "Instant" when every video is only
    /// copied and the whole batch takes under a second.
    static func estimate(_ videos: [VideoTime]) -> Estimate? {
        guard !videos.isEmpty else { return nil }
        // Longest first, each into the runner's video slot that frees up first.
        var slots = [Double](repeating: 0, count: JobRunner.videosAtOnce)
        for video in videos.sorted(by: { $0.seconds > $1.seconds }) {
            slots[slots.indices.min { slots[$0] < slots[$1] }!] += video.seconds
        }
        let total = slots.max()!
        return videos.allSatisfy(\.isCopy) && total < 1 ? .instant : .duration(total)
    }
}
