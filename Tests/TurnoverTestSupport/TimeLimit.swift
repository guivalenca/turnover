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
