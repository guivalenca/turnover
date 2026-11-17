import Synchronization

/// Counts the conversions a `Converter` (and every copy of it) is running, so background work
/// such as refining estimates can step aside for them.
final class ConversionActivity: Sendable {
    private let running = Mutex(0)

    var isBusy: Bool { running.withLock { $0 > 0 } }

    func begin() { running.withLock { $0 += 1 } }
    func end() { running.withLock { $0 -= 1 } }

    /// Returns once no conversion is running, or as soon as the task is cancelled.
    func waitUntilIdle() async {
        while isBusy && !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}
