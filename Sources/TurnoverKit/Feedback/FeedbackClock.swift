/// Tells `Feedback` the time and wakes it later. The app uses `ContinuousFeedbackClock`; tests
/// use a manual clock they move forward by hand, so seconds of waiting take no time at all.
@MainActor
public protocol FeedbackClock: AnyObject {
    /// How long the clock has been running.
    var now: Duration { get }

    /// Runs `action` on the main actor once `now` has reached `time`.
    func run(at time: Duration, _ action: @escaping @MainActor () -> Void)
}

/// Real time, from when the clock was made.
@MainActor
public final class ContinuousFeedbackClock: FeedbackClock {
    private let origin = ContinuousClock.now

    public init() {}

    public var now: Duration { origin.duration(to: .now) }

    public func run(at time: Duration, _ action: @escaping @MainActor () -> Void) {
        let deadline = origin + time
        Task { @MainActor in
            try? await Task.sleep(until: deadline, tolerance: .milliseconds(50), clock: .continuous)
            action()
        }
    }
}
