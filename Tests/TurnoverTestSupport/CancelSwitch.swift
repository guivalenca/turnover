import Synchronization

/// Cancels a task from code that can't see it, such as the task's own progress handler.
///
///     let stop = CancelSwitch()
///     let job = Task { try await Converter().convert(clip, with: MP4Action()) { _ in stop.pull() } }
///     stop.arm(job)
///
/// Pulling before the task is armed cancels it as soon as it is.
public final class CancelSwitch: Sendable {
    private struct State {
        var cancel: (@Sendable () -> Void)?
        var pulled = false
    }

    private let state = Mutex(State())

    public init() {}

    public func arm<Success, Failure>(_ task: Task<Success, Failure>) {
        let pulled = state.withLock { state in
            state.cancel = { task.cancel() }
            return state.pulled
        }
        if pulled { task.cancel() }
    }

    @Sendable public func pull() {
        let cancel = state.withLock { state in
            state.pulled = true
            return state.cancel
        }
        cancel?()
    }
}
