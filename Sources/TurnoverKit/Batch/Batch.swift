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
        Job.meanProgress(of: jobs) ?? (isFinished ? 1 : 0)
    }

    /// The new files, in job order.
    public var outputs: [URL] { jobs.compactMap(\.result?.output) }

    /// Cancels every job that hasn't ended. See `Job.cancel()`.
    public func cancel() {
        for job in jobs { job.cancel() }
    }

    /// Calls `handler` when the last job ends, before `waitUntilFinished()` returns, or right away
    /// if the batch has already ended.
    package func whenFinished(_ handler: @escaping @MainActor (Batch) -> Void) {
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

extension Job {
    /// How much of `jobs` is done, from 0 to 1: the mean of their progress, where a job that
    /// ended counts as done and a skipped file doesn't count. Nil when no job counts.
    package static func meanProgress(of jobs: some Sequence<Job>) -> Double? {
        TurnoverKit.meanProgress(jobs.map { job in
            if case .skipped = job.state { nil } else { job.isFinished ? 1 : job.progress }
        })
    }
}

/// The mean of `fractions`, leaving out the nils (skipped files); nil when all are nil. Shared
/// by batches, the app's menu bar item and the command's progress line.
package func meanProgress(_ fractions: [Double?]) -> Double? {
    let counted = fractions.compactMap(\.self)
    return counted.isEmpty ? nil : counted.reduce(0, +) / Double(counted.count)
}
