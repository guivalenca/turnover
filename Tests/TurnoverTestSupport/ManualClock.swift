import TurnoverKit

/// A `FeedbackClock` that moves only when the test says so. `advance(by:)` runs every action that
/// comes due, in time order, before it returns, so a test sees their effects at once.
@MainActor
public final class ManualClock: FeedbackClock {
    private struct Alarm {
        let time: Duration
        let order: Int
        let action: @MainActor () -> Void
    }

    public private(set) var now: Duration = .zero
    private var alarms: [Alarm] = []
    private var made = 0

    public init() {}

    public func run(at time: Duration, _ action: @escaping @MainActor () -> Void) {
        made += 1
        alarms.append(Alarm(time: time, order: made, action: action))
    }

    /// Moves time forward by `duration`, stopping at each action that comes due to run it.
    public func advance(by duration: Duration) {
        let end = now + duration
        while let next = alarms.filter({ $0.time <= end }).min(by: { ($0.time, $0.order) < ($1.time, $1.order) }) {
            alarms.removeAll { $0.order == next.order }
            now = max(now, next.time)
            next.action()
        }
        now = end
    }
}
