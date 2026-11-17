import Synchronization

/// Where an action reports how far along it is, as a fraction from 0 to 1.
///
/// What reaches the observer is tidied up: values are clamped to 0…1, never go backwards, and
/// come at most once per 0.1%, so an action may report as often as is convenient (every frame,
/// say) and from any thread.
public struct ConversionProgress: Sendable {
    private let sink: Sink

    init(_ handler: @escaping @Sendable (Double) -> Void) {
        sink = Sink(handler)
    }

    /// Reports that `fraction` of the work is done.
    public func report(_ fraction: Double) {
        sink.report(fraction)
    }

    /// Progress nobody watches.
    static var ignored: ConversionProgress { ConversionProgress { _ in } }

    private final class Sink: Sendable {
        private let handler: @Sendable (Double) -> Void
        /// The last value passed on, or -1 before the first.
        private let last = Mutex(-1.0)

        init(_ handler: @escaping @Sendable (Double) -> Void) {
            self.handler = handler
        }

        func report(_ fraction: Double) {
            let fraction = min(max(fraction, 0), 1)
            // The handler runs under the lock, so concurrent reports still arrive in order.
            last.withLock { last in
                guard fraction >= last + 0.001 || (fraction == 1 && last < 1) else { return }
                last = fraction
                handler(fraction)
            }
        }
    }
}
