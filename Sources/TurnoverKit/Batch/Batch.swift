import Foundation
import Observation

/// Files converted together, one `Job` each, started by `JobRunner.run(_:to:)`.
/// Observe it from the main actor, or await `waitUntilFinished()`.
@MainActor @Observable
public final class Batch: Identifiable {
    /// One job per file, in the order the files were given.
    public let jobs: [Job]

    @ObservationIgnored private var waiters: [CheckedContinuation<Void, Never>] = []

    init(jobs: [Job]) {
        self.jobs = jobs
        for job in jobs { job.batch = self }
    }

    /// Whether every job has ended.
    public var isFinished: Bool { jobs.allSatisfy(\.isFinished) }

    /// The new files, in job order.
    public var outputs: [URL] {
        jobs.compactMap { job in
            if case .converted(let result) = job.state { result.output } else { nil }
        }
    }

    /// Cancels every job that hasn't ended. See `Job.cancel()`.
    public func cancel() {
        for job in jobs { job.cancel() }
    }

    /// Returns once every job has ended.
    public func waitUntilFinished() async {
        guard !isFinished else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    /// Called by each job when it ends.
    func jobEnded() {
        guard isFinished else { return }
        let waiters = waiters
        self.waiters = []
        waiters.forEach { $0.resume() }
    }
}
