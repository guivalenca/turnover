import Foundation
import Synchronization

/// A one-line "clip.mov  42%" on standard error, redrawn in place while a slow conversion runs.
/// Shown only when standard error is a terminal; scripts and pipes never see it.
final class ProgressLine: Sendable {
    static let isAvailable = isatty(STDERR_FILENO) == 1

    private let name: String
    /// The percentage on screen, or nil while nothing is.
    private let shown = Mutex<Int?>(nil)

    init(for file: URL) {
        name = file.lastPathComponent
    }

    /// Shows `fraction` done. Completion isn't shown: the finished file's path is printed instead.
    @Sendable func show(_ fraction: Double) {
        guard fraction < 1 else { return }
        let percent = Int(fraction * 100)
        shown.withLock { shown in
            guard shown != percent else { return }
            shown = percent
            write("\r\u{1B}[K\(name)  \(percent)%")
        }
    }

    /// Erases the line, if anything was shown.
    func clear() {
        shown.withLock { shown in
            guard shown != nil else { return }
            shown = nil
            write("\r\u{1B}[K")
        }
    }

    private func write(_ text: String) {
        FileHandle.standardError.write(Data(text.utf8))
    }
}
