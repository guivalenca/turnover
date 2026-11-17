import Observation

/// Records an observable value each time it changes, as a SwiftUI view showing it would see it.
///
///     let overall = Recording { batch.progress }
///     …
///     #expect(overall.values.first == 0)
@MainActor
public final class Recording<Value> {
    public private(set) var values: [Value] = []
    private let read: @MainActor () -> Value

    public init(_ read: @escaping @MainActor () -> Value) {
        self.read = read
        record()
    }

    private func record() {
        let value = withObservationTracking(read) {
            Task { @MainActor in self.record() }
        }
        values.append(value)
    }
}
