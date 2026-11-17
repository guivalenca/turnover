/// Waits until `condition` holds, checking every few milliseconds on the main actor. False if it
/// still doesn't after `timeout`, so a test fails instead of hanging.
@MainActor
public func eventually(timeout: Duration = .seconds(10), _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        guard ContinuousClock.now < deadline else { return false }
        try? await Task.sleep(for: .milliseconds(2))
    }
    return true
}
