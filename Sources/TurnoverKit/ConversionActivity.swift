import Foundation
import Synchronization

/// Counts the conversions a `Converter` (and every copy of it) is running, so background work
/// such as refining estimates can step aside for them.
final class ConversionActivity: Sendable {
    private struct State {
        var running = 0
        /// Who waits for `running` to reach 0.
        var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]
    }

    private let state = Mutex(State())

    var isBusy: Bool { state.withLock { $0.running > 0 } }

    func begin() { state.withLock { $0.running += 1 } }

    func end() {
        let idle = state.withLock { state -> [CheckedContinuation<Void, Never>] in
            state.running -= 1
            guard state.running == 0 else { return [] }
            defer { state.waiters = [:] }
            return Array(state.waiters.values)
        }
        for waiter in idle { waiter.resume() }
    }

    /// Returns once no conversion is running, or as soon as the task is cancelled.
    func waitUntilIdle() async {
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                // Checked under the lock that `end()` and the cancellation handler take, so the
                // waiter is either resumed here or found by one of them, never missed.
                let resumeNow = state.withLock { state in
                    guard state.running > 0, !Task.isCancelled else { return true }
                    state.waiters[id] = continuation
                    return false
                }
                if resumeNow { continuation.resume() }
            }
        } onCancel: {
            state.withLock { $0.waiters.removeValue(forKey: id) }?.resume()
        }
    }
}
