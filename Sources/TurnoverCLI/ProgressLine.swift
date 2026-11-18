import Foundation
import Synchronization
import TurnoverKit

/// A one-line "clip.mov  42%" (or "3 files  42%") on standard error, redrawn in place while a
/// batch runs. Shown only when standard error is a terminal; scripts and pipes never see it.
///
/// It is drawn from the conversions' own threads, as they report, so it keeps moving even when
/// the main thread gets little time (as on a loaded machine running turnover at low priority).
final class ProgressLine: Sendable {
    static let isAvailable = isatty(STDERR_FILENO) == 1

    private struct State {
        /// Each job's fraction done.
        var fractions: [Double]
        /// Whether each job counts towards the total: skipped files don't.
        var counted: [Bool]
        /// The percentage on screen, or nil while nothing is.
        var shown: Int?
    }

    private let label: String
    private let state: Mutex<State>

    init(label: String, jobs: Int) {
        self.label = label
        state = Mutex(State(fractions: Array(repeating: 0, count: jobs), counted: Array(repeating: true, count: jobs)))
    }

    /// Takes job `job`'s progress, from any thread, and redraws if the percentage changed.
    /// Nothing is shown at 0 (quick jobs never draw) or at 1 (the new files' paths are printed).
    func report(_ job: Int, _ fraction: Double) {
        state.withLock { state in
            state.fractions[job] = max(state.fractions[job], fraction)
            let fractions = state.fractions.indices.map { state.counted[$0] ? state.fractions[$0] : nil }
            guard let total = meanProgress(fractions), total > 0, total < 1 else { return }
            let percent = Int(total * 100)
            guard state.shown != percent else { return }
            state.shown = percent
            write("\r\u{1B}[K\(label)  \(percent)%")
        }
    }

    /// Records that job `job` ended: done, or left out of the total if it was skipped.
    func ended(_ job: Int, skipped: Bool) {
        state.withLock { state in
            if skipped { state.counted[job] = false } else { state.fractions[job] = 1 }
        }
    }

    /// Erases the line, runs `body` (which prints a result), and lets the next report redraw,
    /// so that a redraw never lands in the middle of a printed line.
    func clearing(_ body: () -> Void) {
        state.withLock { state in
            if state.shown != nil {
                write("\r\u{1B}[K")
                state.shown = nil
            }
            body()
        }
    }

    private func write(_ text: String) {
        FileHandle.standardError.write(Data(text.utf8))
    }
}
