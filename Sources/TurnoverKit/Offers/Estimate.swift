import Foundation

/// How big a conversion's output will be, or how long it will take. Approximate unless it is an
/// `exactSize`, and `label` says which.
public enum Estimate: Sendable, Hashable {
    /// The output's approximate size, in bytes. Image targets carry this until it is measured.
    case size(Int)
    /// The output's size in bytes, measured by encoding the real output in memory.
    case exactSize(Int)
    /// About a second or less: videos that are only copied into the new container.
    case instant
    /// The time the conversion takes, in seconds. Videos that are re-encoded carry this.
    case duration(Double)

    /// "~31 KB", "~1.2 MB", "~19 MB" (exact sizes drop the "~": "19 MB"); "Instant"; "About 5 s",
    /// "About 2 min". Sizes use Finder's units (1 KB = 1000 bytes).
    public var label: String {
        switch self {
        case .size(let bytes):
            String(localized: "~\(Self.sizeLabel(bytes))", bundle: .turnoverKit,
                   comment: "An approximate size, from a guess: “~19 MB”.")
        case .exactSize(let bytes):
            Self.sizeLabel(bytes)
        case .instant:
            String(localized: "Instant", bundle: .turnoverKit,
                   comment: "How long converting takes when the video is only copied into the new file.")
        case .duration(let seconds):
            Self.durationLabel(seconds)
        }
    }

    /// True for a measured size; every other estimate is approximate.
    public var isExact: Bool {
        if case .exactSize = self { true } else { false }
    }

    /// The size in bytes, exact or not; nil for times.
    public var bytes: Int? {
        switch self {
        case .size(let bytes), .exactSize(let bytes): bytes
        case .instant, .duration: nil
        }
    }

    private static func sizeLabel(_ bytes: Int) -> String {
        var value = Double(bytes) / 1000
        var unit = 0
        while value >= 999.5 && unit < 3 {
            value /= 1000
            unit += 1
        }
        // One decimal below 10 MB ("1.2 MB"), whole numbers otherwise; KB are always whole.
        let number = unit > 0 && value < 9.95 ? String(format: "%.1f", value) : String(Int(max(1, value.rounded())))
        let comment: StaticString = "A size in Finder's units (1 KB = 1000 bytes): “19 MB”."
        return switch unit {
        case 0: String(localized: "\(number) KB", bundle: .turnoverKit, comment: comment)
        case 1: String(localized: "\(number) MB", bundle: .turnoverKit, comment: comment)
        case 2: String(localized: "\(number) GB", bundle: .turnoverKit, comment: comment)
        default: String(localized: "\(number) TB", bundle: .turnoverKit, comment: comment)
        }
    }

    private static func durationLabel(_ seconds: Double) -> String {
        let wholeSeconds = max(1, Int(seconds.rounded(.up)))
        guard wholeSeconds >= 60 else {
            return String(localized: "About \(wholeSeconds) s", bundle: .turnoverKit,
                          comment: "How long converting takes, in seconds, abbreviated.")
        }
        return String(localized: "About \(Int((seconds / 60).rounded())) min", bundle: .turnoverKit,
                      comment: "How long converting takes, in minutes, abbreviated.")
    }
}
