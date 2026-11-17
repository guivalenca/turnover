import Synchronization

/// Collects the progress fractions a conversion reports, from whatever thread reports them.
/// Pass `recorder.record` as the progress handler.
public final class ProgressRecorder: Sendable {
    private let reports = Mutex<[Double]>([])

    public init() {}

    @Sendable public func record(_ fraction: Double) {
        reports.withLock { $0.append(fraction) }
    }

    /// Everything reported so far, in order.
    public var values: [Double] { reports.withLock { $0 } }

    /// The values strictly between 0 and 1.
    public var inBetween: [Double] { values.filter { $0 > 0 && $0 < 1 } }
}
