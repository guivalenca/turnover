import Foundation

/// How big a conversion's output will be, or how long it will take. Always approximate, and
/// `label` says so.
public enum Estimate: Sendable, Hashable {
    /// The output's size, in bytes. Image targets carry this.
    case size(Int)
    /// About a second or less: videos that are only copied into the new container.
    case instant
    /// The time the conversion takes, in seconds. Videos that are re-encoded carry this.
    case duration(Double)

    /// "~31 KB", "~1.2 MB", "~19 MB"; "Instant"; "About 5 s", "About 2 min". Sizes use Finder's
    /// units (1 KB = 1000 bytes).
    public var label: String {
        switch self {
        case .size(let bytes): Self.sizeLabel(bytes)
        case .instant: "Instant"
        case .duration(let seconds): Self.durationLabel(seconds)
        }
    }

    private static func sizeLabel(_ bytes: Int) -> String {
        let units = ["KB", "MB", "GB", "TB"]
        var value = Double(bytes) / 1000
        var unit = 0
        while value >= 999.5 && unit < units.count - 1 {
            value /= 1000
            unit += 1
        }
        // One decimal below 10 MB ("1.2 MB"), whole numbers otherwise; KB are always whole.
        let number = unit > 0 && value < 9.95 ? String(format: "%.1f", value) : String(Int(max(1, value.rounded())))
        return "~\(number) \(units[unit])"
    }

    private static func durationLabel(_ seconds: Double) -> String {
        let wholeSeconds = max(1, Int(seconds.rounded(.up)))
        guard wholeSeconds >= 60 else { return "About \(wholeSeconds) s" }
        return "About \(Int((seconds / 60).rounded())) min"
    }
}
