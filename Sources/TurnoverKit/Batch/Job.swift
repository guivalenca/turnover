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
    }

    /// The file to convert. It is never modified.
    public let source: URL
    public internal(set) var state: State = .waiting

    @ObservationIgnored private var waiters: [CheckedContinuation<Void, Never>] = []

    init(source: URL) {
        self.source = source
    }

    /// Returns once the job has ended.
    public func waitUntilFinished() async {
        guard !isFinished else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    /// Ends the job: sets its final state and wakes whoever waits for it.
    func end(as state: State) {
        self.state = state
        let waiters = waiters
        self.waiters = []
        waiters.forEach { $0.resume() }
    }

    /// Whether the job has ended, whatever the outcome.
    public var isFinished: Bool {
        switch state {
        case .waiting, .running: false
        case .converted, .failed, .skipped: true
        }
    }
}
