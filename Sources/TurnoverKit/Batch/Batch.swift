import Foundation
import Observation

/// Files converted together, one `Job` each, started by `JobRunner.run(_:to:)`.
/// Observe it from the main actor, or await `waitUntilFinished()`.
@MainActor @Observable
public final class Batch: Identifiable {
    /// One job per file, in the order the files were given.
    public let jobs: [Job]
    /// When the batch was started.
    public let startDate = Date()
    /// When its last job ended, or nil while it runs.
    public private(set) var finishDate: Date?

    /// Called once each, in order, when the last job ends, before anyone waiting is woken.
    @ObservationIgnored private var finishHandlers: [@MainActor (Batch) -> Void] = []
    @ObservationIgnored private var waiters: [CheckedContinuation<Void, Never>] = []

    init(jobs: [Job]) {
        self.jobs = jobs
        for job in jobs { job.batch = self }
        if jobs.isEmpty { finishDate = startDate }
    }

    /// Whether every job has ended.
    public var isFinished: Bool { jobs.allSatisfy(\.isFinished) }

    /// How much of the batch is done, from 0 to 1: the mean of its jobs' progress, where a job
    /// that ended counts as done. Skipped files don't count. It never goes backwards.
    public var progress: Double {
        let counted = jobs.filter { if case .skipped = $0.state { false } else { true } }
        guard !counted.isEmpty else { return isFinished ? 1 : 0 }
        return counted.map { $0.isFinished ? 1 : $0.progress }.reduce(0, +) / Double(counted.count)
    }

    /// The new files, in job order.
    public var outputs: [URL] { jobs.compactMap(\.result?.output) }

    /// Cancels every job that hasn't ended. See `Job.cancel()`.
    public func cancel() {
        for job in jobs { job.cancel() }
    }

    /// Calls `handler` when the last job ends, before `waitUntilFinished()` returns, or right away
    /// if the batch has already ended.
    func whenFinished(_ handler: @escaping @MainActor (Batch) -> Void) {
        if finishDate != nil { handler(self) } else { finishHandlers.append(handler) }
    }

    /// Returns once every job has ended.
    public func waitUntilFinished() async {
        guard !isFinished else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    /// Called by each job when it ends.
    func jobEnded() {
        guard isFinished, finishDate == nil else { return }
        finishDate = Date()
        let handlers = finishHandlers
        finishHandlers = []
        handlers.forEach { $0(self) }
        let waiters = waiters
        self.waiters = []
        waiters.forEach { $0.resume() }
    }
}
