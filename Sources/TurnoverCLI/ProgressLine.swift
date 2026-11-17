import Foundation
import Observation
import TurnoverKit

/// A one-line "clip.mov  42%" (or "3 files  42%") on standard error, redrawn in place while a
/// batch runs. Shown only when standard error is a terminal; scripts and pipes never see it.
@MainActor
final class ProgressLine {
    static let isAvailable = isatty(STDERR_FILENO) == 1

    private let label: String
    /// The percentage on screen, or nil while nothing is.
    private var shown: Int?

    init(label: String) {
        self.label = label
    }

    /// Shows `batch`'s progress from now on, each time it changes.
    func follow(_ batch: Batch) {
        let fraction = withObservationTracking { batch.progress } onChange: {
            Task { @MainActor in self.follow(batch) }
        }
        show(fraction)
    }

    /// Shows `fraction` done. Nothing is shown at 0 (quick jobs never draw) or at 1 (the new
    /// files' paths are printed instead).
    func show(_ fraction: Double) {
        guard fraction > 0, fraction < 1 else { return }
        let percent = Int(fraction * 100)
        guard shown != percent else { return }
        shown = percent
        write("\r\u{1B}[K\(label)  \(percent)%")
    }

    /// Erases the line, if anything was shown. It comes back with the next change.
    func clear() {
        guard shown != nil else { return }
        shown = nil
        write("\r\u{1B}[K")
    }

    private func write(_ text: String) {
        FileHandle.standardError.write(Data(text.utf8))
    }
}
