import Foundation
import Synchronization
import TurnoverKit
import UniformTypeIdentifiers

/// Holds conversions at their very end, so a test can see how many run at once and stop one
/// while it runs, whatever the speed of the machine.
///
///     let turnstile = Turnstile()
///     let batch = JobRunner().run(clips, to: [turnstile.holding(MP4Action())])
///     #expect(await turnstile.waitUntil(running: 2))
///     turnstile.open()
public final class Turnstile: Sendable {
    private struct State {
        var running = 0
        var mostAtOnce = 0
        var isOpen = false
    }

    private let state = Mutex(State())

    public init() {}

    /// An action that converts like `action` does, writing its whole output, then waits here
    /// until the turnstile opens. It counts as running all along. Cancelling its job while it
    /// waits makes it throw `CancellationError`, as a real conversion stopped midway would.
    public func holding<Action: ConversionAction>(_ action: Action) -> some ConversionAction {
        Held(wrapped: action, turnstile: self)
    }

    /// How many conversions are running now.
    public var running: Int { state.withLock { $0.running } }

    /// The most that ever ran at once.
    public var mostAtOnce: Int { state.withLock { $0.mostAtOnce } }

    /// Lets every conversion through, now and from now on.
    public func open() {
        state.withLock { $0.isOpen = true }
    }

    /// Waits until at least `count` conversions are running. False if that doesn't happen in time.
    public func waitUntil(running count: Int, timeout: Duration = .seconds(10)) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while running < count {
            guard ContinuousClock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(2))
        }
        return true
    }

    fileprivate func run(_ work: () async throws -> Void) async throws {
        state.withLock { state in
            state.running += 1
            state.mostAtOnce = max(state.mostAtOnce, state.running)
        }
        defer { state.withLock { $0.running -= 1 } }
        try await work()
        while !state.withLock({ $0.isOpen }) {
            try await Task.sleep(for: .milliseconds(2))
        }
    }
}

private struct Held<Wrapped: ConversionAction>: ConversionAction {
    let wrapped: Wrapped
    let turnstile: Turnstile

    var name: String { wrapped.name }
    var outputType: UTType { wrapped.outputType }
    var fileExtension: String { wrapped.fileExtension }

    func accepts(_ file: SourceFile) -> Bool { wrapped.accepts(file) }

    func perform(_ file: SourceFile, writingTo destination: URL) async throws {
        try await turnstile.run { try await wrapped.perform(file, writingTo: destination) }
    }

    func perform(_ file: SourceFile, writingTo destination: URL, progress: ConversionProgress) async throws {
        try await turnstile.run { try await wrapped.perform(file, writingTo: destination, progress: progress) }
    }
}
