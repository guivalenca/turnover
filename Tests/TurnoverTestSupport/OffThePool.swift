import Dispatch

/// Runs `work`, which blocks for a while (making a big image, waiting for a command to exit), on a
/// dispatch queue, keeping Swift concurrency's few threads (three on CI) free for the tests running
/// alongside. A test that blocks one of them for seconds stalls everything async in the process:
/// on CI, two commands waited for on those threads once held a cancelled job for over 10 s.
public func offThePool<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global().async { continuation.resume(with: Result { try work() }) }
    }
}
