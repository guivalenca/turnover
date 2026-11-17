import Foundation
import Observation

/// One file in a batch: what it becomes and how far along it is. Observe it from the main actor.
@MainActor @Observable
public final class Job: Identifiable {
    public enum State: Sendable, Equatable {
        /// Not started yet.
        case waiting
        /// Converting now.
        case running
        /// Done: the new file is at `result.output`.
        case converted(ConversionResult)
        /// Couldn't be converted. The reason is short and starts with the file name, ready for a
        /// notification or a terminal line.
        case failed(reason: String)
        /// Not converted because none of the batch's targets fits the file: it is of another kind,
        /// already in the target format, or neither an image nor a video. The error says which.
        case skipped(ConversionError)
        /// Stopped by `cancel()`. Nothing was written.
        case cancelled
    }

    /// The file to convert. It is never modified.
    public let source: URL
    public private(set) var state: State = .waiting
    /// How much of the conversion is done, from 0 to 1. It never goes backwards and reaches 1
    /// when the job converts. Images jump from 0 to 1; videos rise frame by frame.
    public private(set) var progress: Double = 0

    /// The batch to tell when the job ends.
    @ObservationIgnored weak var batch: Batch?
    /// The conversion, while it runs.
    @ObservationIgnored var task: Task<Void, Never>?
    @ObservationIgnored private var waiters: [CheckedContinuation<Void, Never>] = []

    init(source: URL) {
        self.source = source
    }

    /// Whether the job has ended, whatever the outcome.
    public var isFinished: Bool {
        switch state {
        case .waiting, .running: false
        case .converted, .failed, .skipped, .cancelled: true
        }
    }

    /// Stops the job. A waiting job never starts. A running one stops within moments, and its
    /// partial output is deleted; if it was already moving its output into place, it ends
    /// converted instead. Does nothing to a job that has ended.
    public func cancel() {
        switch state {
        case .waiting: end(as: .cancelled)
        case .running: task?.cancel()
        default: break
        }
    }

    /// Returns once the job has ended.
    public func waitUntilFinished() async {
        guard !isFinished else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func start(_ task: Task<Void, Never>) {
        state = .running
        self.task = task
    }

    /// Takes a progress report from the conversion, on any thread.
    nonisolated func report(_ fraction: Double) {
        Task { @MainActor in
            guard self.state == .running else { return }
            self.progress = max(self.progress, fraction)
        }
    }

    /// Ends the job, unless it has already ended: sets its final state and wakes whoever waits.
    func end(as state: State) {
        guard !isFinished else { return }
        self.state = state
        if case .converted = state { progress = 1 }
        task = nil
        let waiters = waiters
        self.waiters = []
        waiters.forEach { $0.resume() }
        batch?.jobEnded()
    }
}
