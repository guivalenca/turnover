import Foundation
import Observation
import TurnoverKit

/// What the app shows about the batches it runs: a menu bar item while a batch takes more than
/// about a second, and notifications for slow batches, failures and outputs saved to Downloads.
/// Quick batches get nothing. Give it every batch, and observe it from the main actor.
///
/// Give it batches of files offered for their targets only (a Finder menu item's or a ring
/// entry's files): a file the batch skips is then reported as a failure, since the user asked
/// for it and nothing happened.
@MainActor @Observable
public final class Feedback {
    /// How long a batch runs before the menu bar item appears.
    public static let statusItemDelay: Duration = .seconds(1)
    /// How long the item stays, at 100%, after everything has ended.
    public static let statusItemLinger: Duration = .seconds(1.5)

    /// Whether the menu bar item should show now.
    public private(set) var showsStatusItem = false

    /// The batches the item reports on: those started since it last went away, ended or not.
    private var batches: [Batch] = []

    @ObservationIgnored private let clock: any FeedbackClock
    @ObservationIgnored private let notify: @MainActor (Notice) -> Void
    @ObservationIgnored private var lastEnd: Duration = .zero

    /// `notify` posts each notice as its batch ends.
    public init(clock: any FeedbackClock = ContinuousFeedbackClock(),
                notify: @escaping @MainActor (Notice) -> Void = { _ in }) {
        self.clock = clock
        self.notify = notify
    }

    /// Follows `batch` from now until it ends.
    public func track(_ batch: Batch) {
        if isIdle { batches = [] }  // a new round; a lingering item stays and starts again from 0
        batches.append(batch)
        clock.run(at: clock.now + Self.statusItemDelay) { [weak self] in
            if !batch.isFinished { self?.showsStatusItem = true }
        }
        let start = clock.now
        batch.whenFinished { [weak self] batch in self?.ended(batch, startedAt: start) }
    }

    /// How much of the batches shown is done, from 0 to 1: the mean of their jobs' progress,
    /// where a job that ended counts as done. Skipped files don't count.
    public var progress: Double {
        Job.meanProgress(of: batches.flatMap(\.jobs)) ?? (isIdle ? 1 : 0)
    }

    /// The jobs converting now, oldest batch first: the menu's rows, each with a ✕ (`Job.cancel()`).
    public var runningJobs: [Job] { batches.flatMap(\.jobs).filter { $0.state == .running } }

    /// The jobs queued behind them, for example a third video while two convert.
    public var waitingJobs: [Job] { batches.flatMap(\.jobs).filter { $0.state == .waiting } }

    /// Cancels every job that hasn't ended. See `Job.cancel()`.
    public func cancelAll() {
        for batch in batches { batch.cancel() }
    }

    private var isIdle: Bool { batches.allSatisfy(\.isFinished) }

    private func ended(_ batch: Batch, startedAt start: Duration) {
        Notice.notices(for: batch, took: clock.now - start).forEach(notify)
        guard isIdle else { return }
        guard showsStatusItem else {
            batches = []
            return
        }
        lastEnd = clock.now
        clock.run(at: lastEnd + Self.statusItemLinger) { [weak self] in self?.hideIfStillIdle() }
    }

    private func hideIfStillIdle() {
        guard isIdle, clock.now >= lastEnd + Self.statusItemLinger else { return }
        showsStatusItem = false
        batches = []
    }
}
