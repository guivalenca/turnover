import Foundation

/// The limit a speed test asserts: `limit` on a developer Mac, four times that on CI.
///
/// GitHub's macOS runners are 3-core virtual machines with software codecs, and they run every
/// test of every target at once in one process, so a timing there measures the other tests as
/// much as the code under test. CI still catches a slowdown of an order of magnitude; the real
/// limits are checked by running the tests locally.
public func timeLimit(_ limit: Duration) -> Duration {
    ProcessInfo.processInfo.environment["CI"] == nil ? limit : limit * 4
}

/// How fast `work` can run: the fastest of up to `rounds` runs, stopping at the first that beats
/// `limit`.
///
/// While other tests share the CPU (on CI, three cores for all of them), any one run may be slowed
/// many times over, and a few runs back to back can all land in a busy moment. Code that got
/// slower is slow on every run, so it still fails.
public func fastestRun(
    beating limit: Duration, rounds: Int = 20, isolation: isolated (any Actor)? = #isolation,
    _ work: () async throws -> Void
) async rethrows -> Duration {
    var fastest = Duration.seconds(Int64.max)
    for _ in 1...rounds {
        let start = ContinuousClock.now
        try await work()
        fastest = min(fastest, ContinuousClock.now - start)
        if fastest < limit { break }
    }
    return fastest
}
